require 'proxy/puppet_ssl'
require 'puppet_proxy_puppet_api/ssl_forwarder_request'

module Proxy::PuppetApi
  class SslApi < ::Sinatra::Base
    helpers ::Proxy::Helpers

    before do
      cn = https_cert_cn
      allowed = ::Proxy::PuppetSsl.trusted_hosts.map(&:downcase)
      log_halt 403, "Untrusted client #{cn} attempted to access #{request.path_info}. Check puppet_ssl_trusted_hosts in puppet_proxy_puppet_api.yml" unless allowed.include?(cn.downcase)
    end

    post '/puppet/reports' do
      relay { SslForwarderRequest.new.forward_post('/api/config_reports', request) }
    end

    post '/puppet/facts' do
      relay { SslForwarderRequest.new.forward_post('/api/hosts/facts', request) }
    end

    get '/puppet/node/:certname' do
      relay { SslForwarderRequest.new.forward_get("/node/#{params[:certname]}", request, :format => 'yml') }
    end

    post '/puppet/ca/validate' do
      entry = ::Proxy::Plugins.instance.find { |p| p[:name] == :puppetca }
      log_halt 501, "PuppetCA module is not enabled" unless entry && entry[:state] == :running

      autosigner = entry[:di_container].get_dependency(:autosigner)
      log_halt 501, "Provider only supports trivial autosigning" unless autosigner.respond_to?(:validate_csr)

      request.body.rewind
      autosigner.validate_csr(request.body.read) ? 200 : 404
    rescue StandardError => e
      logger.exception "Failed to validate CSR", e
      log_halt 406, e, "Failed to validate CSR"
    end

    private

    def relay
      response = yield
      status response.code.to_i
      content_type response['content-type'] if response['content-type']
      response.body
    rescue StandardError => e
      logger.exception "Error forwarding puppet request to Foreman", e
      log_halt 502, "Could not forward request to Foreman: #{e.message}"
    end
  end
end
