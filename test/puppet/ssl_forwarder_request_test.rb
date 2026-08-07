require 'test_helper'
require 'rack'
require 'puppet_proxy_puppet_api/ssl_forwarder_request'

class SslForwarderRequestTest < Test::Unit::TestCase
  def setup
    @foreman_url = 'https://foreman.example.com'
    Proxy::SETTINGS.stubs(:foreman_url).returns(@foreman_url)
    @request = Proxy::PuppetApi::SslForwarderRequest.new
  end

  def rack_request(env = {})
    Rack::Request.new(Rack::MockRequest.env_for('/whatever', env))
  end

  def test_forward_post_relays_body_and_headers
    stub_request(:post, "#{@foreman_url}/api/config_reports")
      .with(:body => '{"config_report":{}}', :headers => {'X-Custom' => 'value'})
      .to_return(:status => 200, :body => 'ok')

    env = {:input => '{"config_report":{}}', 'HTTP_X_CUSTOM' => 'value'}
    result = @request.forward_post('/api/config_reports', rack_request(env))

    assert_equal '200', result.code
    assert_equal 'ok', result.body
  end

  def test_forward_get_adds_query_and_forwards_headers
    stub_request(:get, "#{@foreman_url}/node/host.example.com?format=yml")
      .with(:headers => {'X-Custom' => 'value'})
      .to_return(:status => 200, :body => '--- {}')

    env = {'HTTP_X_CUSTOM' => 'value'}
    result = @request.forward_get('/node/host.example.com', rack_request(env), :format => 'yml')

    assert_equal '200', result.code
    assert_equal '--- {}', result.body
  end

  def test_forward_post_relays_non_success_response_verbatim
    stub_request(:post, "#{@foreman_url}/api/hosts/facts").to_return(:status => 422, :body => 'invalid')

    result = @request.forward_post('/api/hosts/facts', rack_request(:input => '{}'))

    assert_equal '422', result.code
    assert_equal 'invalid', result.body
  end
end
