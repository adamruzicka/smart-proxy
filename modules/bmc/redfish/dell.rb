module RedfishVendorOverridesDellInc

  def powercycle
    # ForceRestart was added in Lifecycle Controller 3.30.30.30
    # prior to that, it required ForceOff followed by On.
    if host.System.Members[0].Actions['#ComputerSystem.Reset']['ResetType@RedfishAllowableValues'].include? 'ForceRestart'
      poweraction('ForceRestart')
    else
      poweraction('ForceOff')
      # REVIEW - I wonder if any kind of delay is needed for this to be reliable.
      poweraction('On')
    end
  end

  def reset
    host.Managers.Members[0].post({ 'Actions' => 'GracefulRestart' })
  end

end
