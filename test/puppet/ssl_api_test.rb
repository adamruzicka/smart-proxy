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
end
