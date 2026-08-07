require 'test_helper'
require 'proxy/puppet_ssl'

class PuppetSslTest < Test::Unit::TestCase
  def full_settings
    {:puppet_ssl_ca => '/ca.pem', :puppet_ssl_cert => '/cert.pem', :puppet_ssl_key => '/key.pem',
     :puppet_ssl_port => 8140, :puppet_ssl_trusted_hosts => ['puppet.example.com']}
  end

  def test_settings_returns_settings_when_puppet_plugin_running
    entry = {:name => :puppet, :state => :running, :settings => full_settings}
    ::Proxy::Plugins.instance.expects(:find).returns(entry)
    assert_equal full_settings, ::Proxy::PuppetSsl.settings
  end

  def test_settings_returns_nil_when_puppet_plugin_not_found
    ::Proxy::Plugins.instance.expects(:find).returns(nil)
    assert_nil ::Proxy::PuppetSsl.settings
  end

  def test_enabled_true_when_fully_configured
    ::Proxy::PuppetSsl.stubs(:settings).returns(full_settings)
    assert ::Proxy::PuppetSsl.enabled?
  end

  def test_enabled_false_when_settings_missing
    ::Proxy::PuppetSsl.stubs(:settings).returns(nil)
    assert !::Proxy::PuppetSsl.enabled?
  end

  def test_enabled_false_when_port_not_configured
    ::Proxy::PuppetSsl.stubs(:settings).returns(full_settings.merge(:puppet_ssl_port => nil))
    assert !::Proxy::PuppetSsl.enabled?
  end

  def test_trusted_hosts_returns_configured_list
    ::Proxy::PuppetSsl.stubs(:settings).returns(full_settings)
    assert_equal ['puppet.example.com'], ::Proxy::PuppetSsl.trusted_hosts
  end

  def test_trusted_hosts_returns_empty_array_when_settings_missing
    ::Proxy::PuppetSsl.stubs(:settings).returns(nil)
    assert_equal [], ::Proxy::PuppetSsl.trusted_hosts
  end

  def test_trusted_hosts_returns_empty_array_when_unset
    ::Proxy::PuppetSsl.stubs(:settings).returns(full_settings.merge(:puppet_ssl_trusted_hosts => nil))
    assert_equal [], ::Proxy::PuppetSsl.trusted_hosts
  end
end
