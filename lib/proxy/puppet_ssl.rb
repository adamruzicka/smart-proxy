# Settings exposed by the puppet plugin group (puppet_proxy_puppet_api provider),
# only present while that plugin group is enabled and running. This ties the puppet
# SSL listener's lifecycle to the rest of the puppet integration instead of giving it
# an independent enable switch.
module Proxy::PuppetSsl
  def self.settings
    entry = ::Proxy::Plugins.instance.find { |p| p[:name] == :puppet && p[:state] == :running }
    entry && entry[:settings]
  end

  def self.enabled?
    s = settings
    !s.nil? && s[:puppet_ssl_ca] && s[:puppet_ssl_cert] && s[:puppet_ssl_key] && s[:puppet_ssl_port]
  end

  def self.trusted_hosts
    Array(settings && settings[:puppet_ssl_trusted_hosts])
  end
end
