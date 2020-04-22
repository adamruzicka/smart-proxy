module RedfishVendorOverridesHPE

  def poweroff(soft=false)
    poweraction( soft ? 'PushPowerButton' : 'ForceOff' )
  end

  # -- See note about dynamic bootdevices in redfish.rb --
  #def bootdevices
  #  # older HPs have the list of supported values at a different location
  #  host.Systems.Members[0].Boot.BootSourceOverrideSupported || super
  #end

end
