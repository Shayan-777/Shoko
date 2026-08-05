# frozen_string_literal: true

require_relative 'boot_dependencies'

module Shoko
  module Composition
    module ContainerFactory
      # Explicit owner of registration behavior. ContainerFactory remains the
      # public entry-point and delegates graph assembly to this stateless object.
      class RegistrationPipeline
        include InfrastructureRegistration
        include PortAndRepositoryRegistration
        include DomainApplicationRegistration
        include ControllerComposition

        def register_all(container, log_config:)
          register_infrastructure(container, log_config)
          apply_runtime_configuration(container)
          register_core_ports(container)
          register_repositories(container)
          register_domain_services(container)
          register_application_services(container)
          register_state_management(container)
          register_library_services(container)
          container
        end

        private

        def lazy_container_service(container, service_name)
          Shoko::Shared::LazyProxy.new { container.resolve(service_name) }
        end
      end
    end
  end
end
