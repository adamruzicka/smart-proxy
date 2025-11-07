require 'test_helper'
require 'launcher'

class LauncherTest < Test::Unit::TestCase
  def setup
    @launcher = Proxy::Launcher.new
  end

  def test_launched_with_sdnotify
    @launcher.logger.expects(:info).with(includes('2 socket(s)'))
    ::SdNotify.expects(:ready)
    @launcher.launched([:app1, :app2])
  end
end
