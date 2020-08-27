module Proxy
  module BMC
    module RedfishAdapters
      class HPE < ::Proxy::BMC::Redfish
        def initialize(host)
          @host = host
        end

        def poweroff(soft = false)
          poweraction(soft ? 'PushPowerButton' : 'ForceOff')
        end

        # -- See note about dynamic bootdevices in redfish.rb --
        # this override will let Foreman get the list of supported boot devices
        # from older HPs, if and when potential boot devices become dynamically discovered
        #
        # def bootdevices
        #   # older HPs have the list of supported values at a different location
        #   system.Boot.BootSourceOverrideSupported || super
        # end
      end
    end
  end
end
