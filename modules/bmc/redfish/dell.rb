module RedfishVendorOverridesDellInc

  def powercycle
    # ForceRestart was added in Lifecycle Controller 3.30.30.30
    # prior to that, it required ForceOff followed by On.
    if host.System.Members[0].Actions['#ComputerSystem.Reset']['ResetType@RedfishAllowableValues'].include? 'ForceRestart'
      poweraction('ForceRestart')
    else
      poweraction('ForceOff')
      # it only takes a couple seconds to force off, but if you send the 'On' action too
      # quickly, you'll get an error that the server is already on, because it hasn't
      # actually shut off yet. fifteen seconds is chosen arbitrarily; hopefully it covers
      # all scenarios.
      sleep 15
      poweraction('On')
    end
  end

  def reset
    host.post(path: host.Managers.Members[0].Actions['#Manager.Reset']['target'], payload: { 'ResetType' => 'GracefulRestart' })
  end

end
