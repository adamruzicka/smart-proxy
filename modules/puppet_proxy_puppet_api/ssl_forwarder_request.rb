require 'proxy/log'
require 'proxy/request'

module Proxy::PuppetApi
  class SslForwarderRequest < ::Proxy::HttpRequest::ForemanRequest
    include ::Proxy::Log

    def forward_post(foreman_path, request)
      send_request(request_factory.create_post(foreman_path, request.body.read, headers(request)))
    end

    def forward_get(foreman_path, request, query = {})
      send_request(request_factory.create_get(foreman_path, query, headers(request)))
    end

    private

    def headers(request)
      request.env.select { |k, _v| k =~ /^HTTP_/ && k !~ /^HTTP_(VERSION|HOST)$/ }.transform_keys { |k| k[5..] }
    rescue Exception => e
      logger.warn "Unable to extract request headers: #{e}"
      {}
    end
  end
end
