require 'uri'

module ::Proxy::PuppetApi
  class PluginConfiguration
    def load_programmable_settings(settings)
      settings[:classes_retriever] = :apiv3
      settings[:environments_retriever] = :apiv3
      if settings[:puppet_ssl_trusted_hosts].nil? || settings[:puppet_ssl_trusted_hosts].empty?
        settings[:puppet_ssl_trusted_hosts] = default_puppet_ssl_trusted_hosts(settings[:puppet_url])
      end
      settings
    end

    def default_puppet_ssl_trusted_hosts(puppet_url)
      [URI.parse(puppet_url.to_s).host].compact
    rescue URI::InvalidURIError
      []
    end

    def load_classes
      require 'puppet_proxy_common/errors'
      require 'puppet_proxy_common/environments_retriever_base'
      require 'puppet_proxy_common/environment'
      require 'puppet_proxy_common/puppet_class'
      require 'puppet_proxy_common/api_request'
      require 'puppet_proxy_puppet_api/v3_api_request'
      require 'puppet_proxy_puppet_api/v3_environments_retriever'
      require 'puppet_proxy_puppet_api/v3_environment_classes_api_classes_retriever'
    end

    def load_dependency_injection_wirings(container_instance, settings)
      container_instance.dependency :environment_retriever_impl,
                                    -> { ::Proxy::PuppetApi::V3EnvironmentsRetriever.new(settings[:puppet_url], settings[:puppet_ssl_ca], settings[:puppet_ssl_cert], settings[:puppet_ssl_key]) }

      container_instance.singleton_dependency :class_retriever_impl,
                                              (lambda do
                                                ::Proxy::PuppetApi::V3EnvironmentClassesApiClassesRetriever.new(
                                                  settings[:puppet_url],
                                                  settings[:puppet_ssl_ca],
                                                  settings[:puppet_ssl_cert],
                                                  settings[:puppet_ssl_key],
                                                  settings[:api_timeout])
                                              end)
    end
  end
end
