module Proxy::PuppetApi
  class Plugin < Proxy::Provider
    default_settings :puppet_ssl_ca => '/var/lib/puppet/ssl/certs/ca.pem', :api_timeout => 30, :puppet_ssl_port => nil

    plugin :puppet_proxy_puppet_api, ::Proxy::VERSION

    load_programmable_settings ::Proxy::PuppetApi::PluginConfiguration
    load_classes ::Proxy::PuppetApi::PluginConfiguration
    load_dependency_injection_wirings ::Proxy::PuppetApi::PluginConfiguration

    validate :puppet_url, :url => true
    expose_setting :puppet_url
    expose_setting :puppet_ssl_ca
    expose_setting :puppet_ssl_cert
    expose_setting :puppet_ssl_key
    expose_setting :puppet_ssl_port
    validate_readable :puppet_ssl_ca, :puppet_ssl_cert, :puppet_ssl_key
  end
end
