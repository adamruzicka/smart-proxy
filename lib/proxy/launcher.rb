require 'proxy/log'
require 'proxy/settings'
require 'proxy/signal_handler'
require 'proxy/log_buffer/trace_decorator'

CIPHERS = ['ECDHE-RSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES256-GCM-SHA384',
           'AES128-GCM-SHA256', 'AES256-GCM-SHA384', 'AES128-SHA256',
           'AES256-SHA256', 'AES128-SHA', 'AES256-SHA'].freeze

module Proxy
  class Launcher
    include ::Proxy::Log

    attr_reader :settings

    def initialize(settings = ::Proxy::SETTINGS)
      @settings = settings
    end

    def http_enabled?
      !settings.http_port.nil?
    end

    def https_enabled?
      settings.ssl_private_key && settings.ssl_certificate && settings.ssl_ca_file
    end

    def plugins
      ::Proxy::Plugins.instance
    end

    def ciphers
      CIPHERS - settings.ssl_disabled_ciphers
    end

    def launch
      raise Exception.new("Both http and https are disabled, unable to start.") unless http_enabled? || https_enabled?

      ::Proxy::PluginInitializer.new(::Proxy::Plugins.instance).initialize_plugins

      case settings.http_server_type
      when 'webrick'
        require 'proxy/launcher/webrick'
        launcher = ::Launcher::Webrick.new(self)
      when 'puma'
        require 'proxy/launcher/puma'
        launcher = ::Launcher::Puma.new(self)
      else
        fail "Unknown http_server_type: #{settings.http_server_type}"
      end

      launcher.launch
    rescue SignalException => e
      logger.debug("Caught #{e}. Exiting")
      raise
    rescue SystemExit
      # do nothing. This is to prevent the exception handler below from catching SystemExit exceptions.
      raise
    rescue Exception => e
      logger.error "Error during startup, terminating", e
      puts "Errors detected on startup, see log for details. Exiting: #{e}"
      exit(1)
    end
  end
end
