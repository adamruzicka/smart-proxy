require 'bmc/bmc_plugin'

module Proxy
  module BMC
    # Just a bunch of stubs
    def installed_providers
      Proxy::BMC::IPMI.providers_installed + ['redfish', 'shell']
    end

    def installed_ipmi_providers
      Proxy::BMC::IPMI.providers_installed
    end

    def providers
      Proxy::BMC::IPMI.providers + ['redfish', 'shell']
    end

    def installed?(provider)
      if provider == 'redfish' or provider == 'shell'
        true
      else
        Proxy::BMC::IPMI.installed?(provider)
      end
    end
  end
end
