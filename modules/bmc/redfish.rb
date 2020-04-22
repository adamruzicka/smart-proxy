require 'redfish_client'
require 'bmc/base'
require 'bmc/redfish/dell'
require 'bmc/redfish/hpe'

module Proxy
  module BMC
    class Redfish < Base
      include Proxy::Log
      include Proxy::Util

      def initialize(args)
        super
        load_vendor_overrides
        @bmc
      end

      def connect(args = { })
        # TODO probably verify should be an option.
        connection = RedfishClient.new("https://#{args[:host]}/", verify: false)
        connection.login(args[:username], args[:password])
        connection
      end

      def load_vendor_overrides
        mfr = manufacturer
        return unless mfr
        mfr.tr!('^A-Za-z', '')
        begin
          mod = Kernel.const_get("RedfishVendorOverrides#{mfr}".to_sym)
        rescue NameError
          # no extensions for this vendor
          return
        end
        logger.debug "Extending Redfish with vendor overrides for #{mfr}"
        self.extend mod
      end

      def manufacturer
        host.Systems.Members[0].Manufacturer
      end

      # returns boolean if the test is successful
      def test
        # pretty low-effort try, here. sufficient, though?
        begin
          host.Managers.Members.any?
        rescue NoMethodError
          false
        end
      end

      def identifystatus
        host.Systems.Members[0].IndicatorLED.downcase
      end

      def identifyon
        host.Systems.Members[0].patch(payload: { 'IndicatorLED' => 'On' })
      end

      def identifyoff
        host.Systems.Members[0].patch(payload: { 'IndicatorLED' => 'Off' })
      end

      def poweroff(soft=false)
        poweraction( soft ? 'GracefulShutdown' : 'ForceOff' )
      end

      def powercycle
        poweraction('ForceRestart')
      end

      def poweron
        poweraction('On')
      end

      def powerstatus
        host.Systems.Members[0].PowerState.downcase
      end

      def poweron?
        powerstatus == 'on'
      end

      def poweroff?
        powerstatus == 'off'
      end

      def bootdevice
        host.Systems.Members[0].Boot['BootSourceOverrideTarget']
      end

      def bootdevices
        # RedFish will tell you which devices can be put in the boot source override
        # but Foreman seems structurally arranged at present for these values to be
        # hardcoded. I can think of a few reasons to continue with that pattern. But
        # if in the future it becomes advantageous to do something more dynamic --
        # this is how to find out:
        #
        #host.Systems.Members.Boot['BootSourceOverrideTarget@Redfish.AllowableValues']
        #
        # Dell gives a list like [ None, Floppy, Cd, Hdd, SDCard, Utilities,
        #                          BiosSetup, Pxe ]
        # HPE -        [ None, Floppy, Cd, Hdd, Usb, Utilities, BiosSetup, Pxe ]
        # SuperMicro - [ None, Pxe, Hdd, Diags, Cd, BiosSetup, FloppyRemovableMedia,
        #                UsbKey, UsbHdd, UsbFloppy, UsbCd, UefiCd, UefiHdd, ... ]
        #
        # For the four devices Foreman hardcodes, lucky for us all three use the same set
        # of values.
        [ 'pxe', 'disk', 'bios', 'cdrom' ]
      end

      def bootdevice=(args={ :device => nil, :reboot => false, :persistent => false })
        devmap = { 'bios'  => 'BiosSetup',
                   'cdrom' => 'Cd',
                   'disk'  => 'Hdd',
                   'pxe'   => 'Pxe' }

        host.Systems.Members[0].patch(
          payload: {
            'Boot' => {
              'BootSourceOverrideTarget' => devmap[args[:device]],
              'BootSourceOverrideEnabled' => args[:persistent] ? 'Enabled' : 'Once'
            }
          })
        powercycle if reboot
      end

      def bootpxe(reboot=false, persistent=false)
        bootdevice = { :device => 'pxe', :reboot => reboot, :persistent => persistent }
      end

      def bootdisk(reboot=false, persistent=false)
        bootdevice = { :device => 'disk', :reboot => reboot, :persistent => persistent }
      end

      def bootbios(reboot=false, persistent=false)
        bootdevice = { :device => 'bios', :reboot => reboot, :persistent => persistent }
      end

      def bootcdrom(reboot=false, persistent=false)
        bootdevice = { :device => 'cdrom', :reboot => reboot, :persistent => persistent }
      end

      def ip
        host.Managers.Members[0].EthernetInterfaces.Members[0].IPv4Addresses.first['Address']
      end

      def mac
        host.Managers.Members[0].EthernetInterfaces.Members[0].MACAddress
      end

      def gateway
        host.Managers.Members[0].EthernetInterfaces.Members[0].IPv4Addresses.first['Gateway']
      end

      def netmask
        host.Managers.Members[0].EthernetInterfaces.Members[0].IPv4Addresses.first['SubnetMask']
      end

      def vlanid
        vlaninfo = host.Managers.Members[0].EthernetInterfaces.Members[0].VLAN
        return unless vlaninfo # some older Proliants don't have a VLAN setting at all.
        return unless vlaninfo.VLANEnable
        vlaninfo.VLANId
      end

      def ipsrc
        host.Managers.Members[0].EthernetInterfaces.Members[0].IPv4Addresses.first['AddressOrigin']
      end

      def guid
        host.Managers.Members[0].UUID
      end

      def version
        host.Managers.Members[0].FirmwareVersion
      end

      def reset
        host.Managers.Members[0].post({ 'Actions' => 'Reset' })
      end

      def model
        host.Systems.Members[0].Model
      end

      def serial
        host.Systems.Members[0].SerialNumber
      end

      def asset_tag
        host.Systems.Members[0].AssetTag
      end

      protected
      attr_reader :host

      private
      def poweraction(action)
        host.Systems.Members[0].post(payload: { 'Action' => 'Reset', 'ResetType' => action })
      end

    end
  end
end
