require 'test_helper'
require 'sinatra/base'
require 'puppet_proxy_puppet_api/ssl_api'

class SslApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::PuppetApi::SslApi.new
  end

  def setup
    @foreman_url = 'https://foreman.example.com'
    Proxy::SETTINGS.stubs(:foreman_url).returns(@foreman_url)
    ::Proxy::PuppetSsl.stubs(:trusted_hosts).returns(['puppetserver.example.com'])
  end

  def https_client_cert_env(common_name)
    OpenSSL::X509::Certificate.stubs(:new).returns(OpenSSL::X509::Certificate)
    OpenSSL::X509::Certificate.stubs(:subject).returns("CN=#{common_name},...")
    {'HTTPS' => 'on', 'SSL_CLIENT_CERT' => 'FOOBAR'}
  end

  def test_allowed_cn_forwards_report_and_relays_response
    stub_request(:post, "#{@foreman_url}/api/config_reports").with(:body => '{"report":true}').to_return(:status => 200, :body => 'ok')

    post '/puppet/reports', '{"report":true}', https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
    assert_equal 'ok', last_response.body
  end

  def test_allowed_cn_forwards_facts
    stub_request(:post, "#{@foreman_url}/api/hosts/facts").with(:body => '{"facts":true}').to_return(:status => 200, :body => 'ok')

    post '/puppet/facts', '{"facts":true}', https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
  end

  def test_allowed_cn_forwards_node_lookup
    stub_request(:get, "#{@foreman_url}/node/host.example.com?format=yml").to_return(:status => 200, :body => '--- {}')

    get '/puppet/node/host.example.com', nil, https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
    assert_equal '--- {}', last_response.body
  end

  def test_disallowed_cn_is_forbidden_without_contacting_foreman
    post '/puppet/reports', '{}', https_client_cert_env('someone-else.example.com')

    assert last_response.forbidden?
  end

  def test_missing_client_cert_is_forbidden
    post '/puppet/reports', '{}', {'HTTPS' => 'on'}

    assert last_response.forbidden?
  end

  def test_foreman_error_response_is_relayed_verbatim
    stub_request(:post, "#{@foreman_url}/api/config_reports").to_return(:status => 422, :body => 'invalid report')

    post '/puppet/reports', '{}', https_client_cert_env('puppetserver.example.com')

    assert_equal 422, last_response.status
    assert_equal 'invalid report', last_response.body
  end

  def test_foreman_unreachable_returns_bad_gateway
    stub_request(:post, "#{@foreman_url}/api/config_reports").to_raise(Errno::ECONNREFUSED)

    post '/puppet/reports', '{}', https_client_cert_env('puppetserver.example.com')

    assert_equal 502, last_response.status
  end

  def format12_report
    {
      'report_format' => 12,
      'host' => 'test.example.com',
      'time' => '2024-01-01T12:00:00Z',
      'status' => 'changed',
      'metrics' => {
        'resources' => {'name' => 'resources', 'label' => 'Resources', 'values' => [
          ['restarted', 'Restarted', 0], ['failed', 'Failed', 0],
          ['failed_to_restart', 'Failed to restart', 0], ['skipped', 'Skipped', 0]
        ]},
        'events' => {'name' => 'events', 'label' => 'Events', 'values' => [['noop', 'Noop', 0], ['total', 'Total', 0]]},
        'changes' => {'name' => 'changes', 'label' => 'Changes', 'values' => [['total', 'Total', 0]]},
      },
      'logs' => [],
    }
  end

  def test_format12_report_is_transformed_before_forwarding
    expected_body = {'config_report' => Proxy::PuppetApi::ReportFormat12Transformer.transform(format12_report)}.to_json
    stub_request(:post, "#{@foreman_url}/api/config_reports").with(:body => expected_body).to_return(:status => 200, :body => 'ok')

    post '/puppet/reports', format12_report.to_json, https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
  end

  def test_non_format12_report_body_passes_through_unchanged
    body = '{"config_report":{"host":"test.example.com"}}'
    stub_request(:post, "#{@foreman_url}/api/config_reports").with(:body => body).to_return(:status => 200, :body => 'ok')

    post '/puppet/reports', body, https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
  end

  def test_non_json_report_body_passes_through_unchanged
    stub_request(:post, "#{@foreman_url}/api/config_reports").with(:body => 'not json at all').to_return(:status => 200, :body => 'ok')

    post '/puppet/reports', 'not json at all', https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
  end

  def test_malformed_format12_report_returns_bad_request_without_contacting_foreman
    post '/puppet/reports', {'report_format' => 12}.to_json, https_client_cert_env('puppetserver.example.com')

    assert_equal 400, last_response.status
  end

  def puppetca_entry(state, autosigner = nil)
    di_container = mock('di_container')
    di_container.stubs(:get_dependency).with(:autosigner).returns(autosigner)
    {:name => :puppetca, :state => state, :di_container => di_container}
  end

  def token_whitelisting_autosigner(valid)
    Class.new do
      define_method(:validate_csr) { |_body| valid }
    end.new
  end

  def hostname_whitelisting_autosigner
    Object.new
  end

  def test_ca_validate_returns_200_for_valid_csr
    ::Proxy::Plugins.instance.stubs(:find).returns(puppetca_entry(:running, token_whitelisting_autosigner(true)))

    post '/puppet/ca/validate', 'csr-body', https_client_cert_env('puppetserver.example.com')

    assert last_response.ok?
  end

  def test_ca_validate_returns_404_for_invalid_csr
    ::Proxy::Plugins.instance.stubs(:find).returns(puppetca_entry(:running, token_whitelisting_autosigner(false)))

    post '/puppet/ca/validate', 'csr-body', https_client_cert_env('puppetserver.example.com')

    assert_equal 404, last_response.status
  end

  def test_ca_validate_returns_not_implemented_when_puppetca_not_running
    ::Proxy::Plugins.instance.stubs(:find).returns(puppetca_entry(:disabled))

    post '/puppet/ca/validate', 'csr-body', https_client_cert_env('puppetserver.example.com')

    assert_equal 501, last_response.status
  end

  def test_ca_validate_returns_not_implemented_when_puppetca_absent
    ::Proxy::Plugins.instance.stubs(:find).returns(nil)

    post '/puppet/ca/validate', 'csr-body', https_client_cert_env('puppetserver.example.com')

    assert_equal 501, last_response.status
  end

  def test_ca_validate_returns_not_implemented_when_autosigner_does_not_support_it
    ::Proxy::Plugins.instance.stubs(:find).returns(puppetca_entry(:running, hostname_whitelisting_autosigner))

    post '/puppet/ca/validate', 'csr-body', https_client_cert_env('puppetserver.example.com')

    assert_equal 501, last_response.status
  end

  def test_ca_validate_disallowed_cn_is_forbidden
    post '/puppet/ca/validate', 'csr-body', https_client_cert_env('someone-else.example.com')

    assert last_response.forbidden?
  end
end
