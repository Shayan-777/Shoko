# frozen_string_literal: true

require 'set'

require_relative '../adapters/storage/background_worker'
require_relative '../adapters/storage/atomic_file_writer'
require_relative '../adapters/monitoring/performance_monitor'
require_relative '../adapters/monitoring/perf_tracer'
require_relative '../adapters/monitoring/logger_adapter'
require_relative '../core/services/null_logger'
require_relative '../adapters/storage/pagination_cache'
require_relative '../adapters/storage/cache_paths'
require_relative '../adapters/storage/epub_cache'
require_relative '../adapters/output/kitty/kitty_image_renderer'
require_relative '../adapters/output/terminal/cli_progress_renderer'
require_relative '../adapters/output/kitty/display_capabilities'
require_relative '../adapters/output/terminal/text_metrics'
require_relative '../adapters/storage/repositories/cached_library_repository'
require_relative '../adapters/output/render_registry'
require_relative '../core/events/domain_event_bus'
require_relative '../core/services/default_display_capabilities'
require_relative '../core/services/inline_executor'
require_relative '../adapters/storage/file_writer_service'
require_relative '../adapters/storage/dictionary_catalog_service'
require_relative '../adapters/storage/sqlite_dictionary_adapter'
require_relative '../adapters/storage/config_storage_adapter'
require_relative '../adapters/output/instrumentation_service'
require_relative '../adapters/output/terminal_capabilities_adapter'
require_relative '../adapters/book_sources/download_service'
require_relative '../adapters/storage/cache_pointer_resolver'
require_relative '../adapters/storage/cache_availability_adapter'
require_relative '../adapters/storage/recent_files_repository'
require_relative '../adapters/storage/file_probe_adapter'
require_relative '../adapters/storage/path_ops_adapter'
require_relative '../adapters/input/command_factory'
require_relative '../adapters/input/key_classifier_adapter'
require_relative '../adapters/output/terminal/text_sanitizer_adapter'
require_relative '../adapters/storage/dictionary_availability_adapter'
require_relative '../adapters/storage/dictionary_storage_adapter'
require_relative '../adapters/storage/data_cleanup_adapter'
require_relative '../adapters/storage/cache_manager_adapter'
require_relative '../adapters/book_sources/book_finder'
require_relative '../adapters/book_sources/metadata_reader_adapter'
require_relative '../adapters/runtime/env_runtime_config_adapter'
require_relative '../adapters/runtime/rexml_security_limits_adapter'
require_relative '../adapters/runtime/process_control_adapter'
require_relative '../adapters/runtime/monotonic_clock_adapter'
require_relative '../adapters/input/input_system_factory_adapter'
require_relative '../adapters/output/ui/rendering_factory_adapter'
require_relative '../core/services/dictionary_service'
require_relative '../core/services/default_terminal_capabilities'
require_relative '../core/services/default_layout_metrics'
require_relative '../adapters/state/config_reader_adapter'
require_relative '../adapters/state/layout_metrics_adapter'
require_relative '../adapters/state/state_writer_adapter'
require_relative '../adapters/state/rendered_content_reader_adapter'
require_relative '../adapters/state/reader_state_reader_adapter'
require_relative '../adapters/state/ui_state_reader_adapter'
require_relative '../adapters/state/render_state_writer_adapter'
require_relative '../adapters/state/progress_state_reader_adapter'
require_relative '../adapters/state/sidebar_state_reader_adapter'
require_relative '../adapters/state/menu_state_reader_adapter'
require_relative '../adapters/state/menu_state_writer_adapter'
require_relative '../adapters/state/notification_writer_adapter'
require_relative '../adapters/state/command_port_adapter'
require_relative '../adapters/state/event_publisher_adapter'
require_relative '../adapters/state/wrapped_lines_provider_adapter'
require_relative 'ui/reader_view_model_builder'
require_relative 'composition/reader_session_context'
require_relative 'composition/menu_session_context'
require_relative 'composition/container_factory/infrastructure_registration'
require_relative 'composition/container_factory/port_and_repository_registration'
require_relative 'composition/container_factory/domain_application_registration'
require_relative 'composition/container_factory/controller_composition'
require_relative 'composition/container_factory/test_container_registration'
require_relative '../adapters/output/ui/component_factory'
require_relative '../adapters/output/ui/sessions/dictionary_ui_session_adapter'
require_relative '../adapters/output/ui/sessions/in_book_search_ui_session_adapter'
require_relative '../adapters/output/ui/sessions/annotation_overlay_ui_session_adapter'
require_relative 'services/popup_position_service'

module Shoko
  module Application
    # Dependency injection container for managing service dependencies.
    class DependencyContainer
      class DependencyError < StandardError; end
      class CircularDependencyError < DependencyError; end

      def initialize
        @services = {}
        @factories = {}
        @singletons = {}
        @resolving = Set.new
      end

      # Register a singleton service
      #
      # @param name [Symbol] Service name
      # @param service [Object] Service instance
      def register(name, service)
        @services[name] = service
      end

      # Register a factory for lazy instantiation
      #
      # @param name [Symbol] Service name
      # @param factory [Proc] Factory proc that creates the service
      def register_factory(name, &factory)
        @factories[name] = factory
      end

      # Register a singleton factory
      #
      # @param name [Symbol] Service name
      # @param factory [Proc] Factory proc
      def register_singleton(name, &factory)
        @singletons[name] = factory
      end

      # Resolve a service by name
      #
      # @param name [Symbol] Service name
      # @return [Object] Service instance
      def resolve(name)
        return @services[name] if @services.key?(name)

        detect_circular_dependency(name) do
          resolve_from_factories(name)
        end
      end

      # Resolve multiple services
      #
      # @param names [Array<Symbol>] Service names
      # @return [Hash<Symbol, Object>] Hash of name => service
      def resolve_many(*names)
        names.to_h { |name| [name, resolve(name)] }
      end

      # Resolve a service by name, returning nil if not registered
      #
      # @param name [Symbol] Service name
      # @return [Object, nil] Service instance or nil
      def resolve_optional(name)
        return nil unless registered?(name)

        resolve(name)
      end

      # Remove a registered service instance
      #
      # @param name [Symbol] Service name
      def unregister(name)
        @services.delete(name)
      end

      # Check if service is registered
      #
      # @param name [Symbol] Service name
      # @return [Boolean]
      def registered?(name)
        @services.key?(name) || @factories.key?(name) || @singletons.key?(name)
      end

      # List all registered service names
      #
      # @return [Array<Symbol>]
      def service_names
        (@services.keys + @factories.keys + @singletons.keys).uniq
      end

      # Create child container with inherited services
      #
      # @return [DependencyContainer]
      def create_child
        child = self.class.new
        child.copy_registrations_from(self)
        child
      end

      # Clear all registrations (for testing)
      def clear!
        @services.clear
        @factories.clear
        @singletons.clear
      end

      # Copy registrations from another container
      # @api private
      def copy_registrations_from(source)
        @services = source.registry_services.dup
        @factories = source.registry_factories.dup
        @singletons = source.registry_singletons.dup
      end

      protected

      def registry_services = @services
      def registry_factories = @factories
      def registry_singletons = @singletons

      private

      def resolve_from_factories(name)
        if @singletons.key?(name)
          @services[name] ||= @singletons[name].call(self)
        elsif @factories.key?(name)
          @factories[name].call(self)
        else
          raise DependencyError, "Service '#{name}' not registered"
        end
      end

      def detect_circular_dependency(name)
        if @resolving.include?(name)
          raise CircularDependencyError,
                "Circular dependency detected for '#{name}'"
        end

        @resolving.add(name)
        begin
          yield
        ensure
          @resolving.delete(name)
        end
      end
    end

    # Factory methods for common service configurations.
    module ContainerFactory
      class << self
        include Shoko::Application::Composition::ContainerFactory::InfrastructureRegistration
        include Shoko::Application::Composition::ContainerFactory::PortAndRepositoryRegistration
        include Shoko::Application::Composition::ContainerFactory::DomainApplicationRegistration
        include Shoko::Application::Composition::ContainerFactory::ControllerComposition
        include Shoko::Application::Composition::ContainerFactory::TestContainerRegistration

        # Create a fully configured dependency container.
        #
        # @param log_config [Hash] Logger configuration from CLI
        # @return [DependencyContainer]
        def create_default_container(log_config: {})
          container = DependencyContainer.new
          event_bus = register_infrastructure(container, log_config)
          apply_runtime_configuration(container)
          register_core_ports(container)
          register_repositories(container)
          register_domain_services(container)
          register_application_services(container)
          register_state_management(container, event_bus)
          register_library_services(container)
          apply_test_configuration(container)
          container
        end
      end
    end
  end
end
