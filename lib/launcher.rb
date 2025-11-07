require 'proxy/log'
require 'proxy/settings'
require 'proxy/signal_handler'
require 'proxy/log_buffer/trace_decorator'
require 'sd_notify'
require 'async'
require 'async/http/endpoint'
require 'falcon/server'
require 'protocol/rack'

CIPHERS = ['ECDHE-RSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES256-GCM-SHA384',
           'AES128-GCM-SHA256', 'AES256-GCM-SHA384', 'AES128-SHA256',
           'AES256-SHA256', 'AES128-SHA', 'AES256-SHA'].freeze

module Proxy
  class Launcher
    include ::Proxy::Log

    attr_reader :settings

    def initialize(settings = SETTINGS)
      @settings = settings
    end

    def http_enabled?
      !settings.http_port.nil?
    end

    def https_enabled?
      settings.ssl_private_key && settings.ssl_certificate && settings.ssl_ca_file
    end

    def plugins
      ::Proxy::Plugins.instance.select { |p| p[:state] == :running }
    end

    def http_plugins
      plugins.select { |p| p[:http_enabled] }.map { |p| p[:class] }
    end

    def https_plugins
      plugins.select { |p| p[:https_enabled] }.map { |p| p[:class] }
    end

    def http_app(http_port, plugins = http_plugins)
      return nil unless http_enabled?
      app = Rack::Builder.new do
        plugins.each { |p| instance_eval(p.http_rackup) }
      end

      http_settings = {
        :app => app,
        :Port => http_port, # only being used to correctly log http port being used
        :Logger => ::Proxy::LogBuffer::TraceDecorator.instance,
      }
      base_app_settings.merge(http_settings)
    end

    def https_app(https_port, plugins = https_plugins)
      unless https_enabled?
        logger.warn "Missing SSL setup, https is disabled."
        return nil
      end

      unless File.readable?(settings.ssl_ca_file)
        logger.error "Unable to read #{settings.ssl_ca_file}. Are the values correct in settings.yml and do permissions allow reading?"
      end

      app = Rack::Builder.new do
        plugins.each { |p| instance_eval(p.https_rackup) }
      end

      ssl_options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
      ssl_options |= OpenSSL::SSL::OP_CIPHER_SERVER_PREFERENCE if defined?(OpenSSL::SSL::OP_CIPHER_SERVER_PREFERENCE)
      # This is required to disable SSLv3 on Ruby 1.8.7
      ssl_options |= OpenSSL::SSL::OP_NO_SSLv2 if defined?(OpenSSL::SSL::OP_NO_SSLv2)
      ssl_options |= OpenSSL::SSL::OP_NO_SSLv3 if defined?(OpenSSL::SSL::OP_NO_SSLv3)
      ssl_options |= OpenSSL::SSL::OP_NO_TLSv1 if defined?(OpenSSL::SSL::OP_NO_TLSv1)
      ssl_options |= OpenSSL::SSL::OP_NO_TLSv1_1 if defined?(OpenSSL::SSL::OP_NO_TLSv1_1)
      # Disable client initiated renegotiation
      ssl_options |= OpenSSL::SSL::OP_NO_RENEGOTIATION if defined?(OpenSSL::SSL::OP_NO_RENEGOTIATION)

      Proxy::SETTINGS.tls_disabled_versions&.each do |version|
        constant = OpenSSL::SSL.const_get("OP_NO_TLSv#{version.to_s.tr('.', '_')}") rescue nil

        if constant
          logger.info "TLSv#{version} will be disabled."
          ssl_options |= constant
        else
          logger.warn "TLSv#{version} was not found."
        end
      end

      https_settings = {
        :app => app,
        :Port => https_port, # only being used to correctly log https port being used
        :Logger => ::Proxy::LogBuffer::Decorator.instance,
        :SSLEnable => true,
        :SSLVerifyClient => OpenSSL::SSL::VERIFY_PEER,
        :SSLPrivateKey => load_ssl_private_key(settings.ssl_private_key),
        :SSLCertificate => load_ssl_certificate(settings.ssl_certificate),
        :SSLCACertificateFile => settings.ssl_ca_file,
        :SSLOptions => ssl_options,
        :SSLCiphers => CIPHERS - Proxy::SETTINGS.ssl_disabled_ciphers,
      }
      base_app_settings.merge(https_settings)
    end

    def load_ssl_private_key(path)
      OpenSSL::PKey.read(File.read(path))
    rescue Exception => e
      logger.error "Unable to load private SSL key. Are the values correct in settings.yml and do permissions allow reading?", e
      raise e
    end

    def load_ssl_certificate(path)
      OpenSSL::X509::Certificate.new(File.read(path))
    rescue Exception => e
      logger.error "Unable to load SSL certificate. Are the values correct in settings.yml and do permissions allow reading?", e
      raise e
    end

    def falcon_server(app, addresses, port)
      rack_app = app[:app]

      # Create endpoint for the given address and port
      endpoint = Async::HTTP::Endpoint.parse("http://#{addresses.first}:#{port}")

      # If SSL is enabled, wrap the endpoint with SSL
      if app[:SSLEnable]
        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.cert = app[:SSLCertificate]
        ssl_context.key = app[:SSLPrivateKey]
        ssl_context.ca_file = app[:SSLCACertificateFile]
        ssl_context.ssl_version = :TLSv1_2_server
        ssl_context.ciphers = app[:SSLCiphers]
        ssl_context.options = app[:SSLOptions]
        ssl_context.verify_mode = app[:SSLVerifyClient]
        
        endpoint = Async::HTTP::Endpoint.parse("https://#{addresses.first}:#{port}", ssl_context: ssl_context)
      end
      
      # Wrap Rack app with Protocol::Rack middleware
      middleware = Protocol::Rack::Adapter.new(rack_app)
      
      # Create and return Falcon server
      Falcon::Server.new(middleware, endpoint)
    end

    def launch
      raise Exception.new("Both http and https are disabled, unable to start.") unless http_enabled? || https_enabled?

      ::Proxy::PluginInitializer.new(::Proxy::Plugins.instance).initialize_plugins

      http_app = http_app(settings.http_port)
      https_app = https_app(settings.https_port)

      servers = []
      servers << falcon_server(https_app, settings.bind_host, settings.https_port) unless https_app.nil?
      servers << falcon_server(http_app, settings.bind_host, settings.http_port) unless http_app.nil?

      Proxy::SignalHandler.install_traps

      # Log that we're launching
      launched(servers)

      # Start all servers in a single async reactor using fibers
      # This is the core benefit of Falcon - fiber-based concurrency
      Async do |task|
        # Start each server in its own fiber and collect the tasks
        server_tasks = servers.map do |server|
          task.async do
            server.run
          end
        end
        
        # Wait for all server tasks (they run indefinitely until interrupted)
        server_tasks.each(&:wait)
      end
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

    def launched(servers)
      logger.info("Smart proxy has launched on #{servers.size} socket(s), waiting for requests")
      SdNotify.ready
    end

    def base_app_settings
      {
        :server => :falcon,
        :DoNotListen => true,
        :ServerSoftware => "foreman-proxy/#{Proxy::VERSION}",
        :daemonize => false,
        :AccessLog => [],
      }
    end
  end
end
