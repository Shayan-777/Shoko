# frozen_string_literal: true

module Shoko
  module Adapters::Input::Controllers
    module Dependencies
      # Groups MenuController collaborators into bounded bundles.
      MenuControllerDependencies = Data.define(:core, :services, :session, :platform) do
        MenuCoreBundle = Data.define(
          :observer_registry,
          :catalog,
          :terminal_service,
          :frame_coordinator,
          :render_pipeline,
          :pagination_orchestrator,
          :menu_ui_dependencies,
          :build_reader_controller,
          :ui_component_factory,
          :key_classifier,
          :input_system_factory,
          :menu_state_reader,
          :menu_state_writer,
          :command_bus
        )

        MenuWorkflowServiceBundle = Data.define(
          :reader_launch_service_factory,
          :download_workflow_factory,
          :dictionary_workflow_factory,
          :annotation_workflow_factory,
          :progress_presenter_factory,
          :background_worker_factory,
          :pagination_cache_preloader
        )

        MenuDomainServiceBundle = Data.define(
          :notification_service,
          :settings_service,
          :annotation_service,
          :logger,
          :download_service,
          :dictionary_catalog_service,
          :text_sanitizer,
          :recent_files_repository,
          :cache_pointer_resolver,
          :document_path_resolver,
          :dictionary_availability,
          :dictionary_storage
        )

        MenuReaderServiceBundle = Data.define(
          :page_calculator,
          :layout_service,
          :wrapping_service,
          :document_service_factory,
          :config_reader,
          :reader_state_reader,
          :state_writer,
          :runtime_config
        )

        MenuServiceBundle = Data.define(
          :workflow,
          :domain,
          :reader_runtime
        )

        MenuSessionBundle = Data.define(
          :reader_session_context,
          :menu_session_context,
          :document
        )

        MenuPlatformBundle = Data.define(
          :file_probe,
          :path_ops,
          :clock,
          :process_control
        )

        MENU_CORE_FIELDS = %i[
          observer_registry
          catalog
          terminal_service
          frame_coordinator
          render_pipeline
          pagination_orchestrator
          menu_ui_dependencies
          build_reader_controller
          ui_component_factory
          key_classifier
          input_system_factory
          menu_state_reader
          menu_state_writer
          command_bus
        ].freeze

        MENU_SERVICE_WORKFLOW_FIELDS = %i[
          reader_launch_service_factory
          download_workflow_factory
          dictionary_workflow_factory
          annotation_workflow_factory
          progress_presenter_factory
          background_worker_factory
          pagination_cache_preloader
        ].freeze

        MENU_SERVICE_DOMAIN_FIELDS = %i[
          notification_service
          settings_service
          annotation_service
          logger
          download_service
          dictionary_catalog_service
          text_sanitizer
          recent_files_repository
          cache_pointer_resolver
          document_path_resolver
          dictionary_availability
          dictionary_storage
        ].freeze

        MENU_SERVICE_READER_RUNTIME_FIELDS = %i[
          page_calculator
          layout_service
          wrapping_service
          document_service_factory
          config_reader
          reader_state_reader
          state_writer
          runtime_config
        ].freeze

        MENU_SERVICE_FIELDS = (
          MENU_SERVICE_WORKFLOW_FIELDS +
          MENU_SERVICE_DOMAIN_FIELDS +
          MENU_SERVICE_READER_RUNTIME_FIELDS
        ).freeze

        MENU_SESSION_FIELDS = %i[
          reader_session_context
          menu_session_context
          document
        ].freeze

        MENU_PLATFORM_FIELDS = %i[
          file_probe
          path_ops
          clock
          process_control
        ].freeze

        MENU_REQUIRED_FIELDS = %i[
          observer_registry
          catalog
          terminal_service
          frame_coordinator
          render_pipeline
          pagination_orchestrator
          menu_ui_dependencies
          build_reader_controller
          ui_component_factory
          key_classifier
          input_system_factory
          menu_state_reader
          menu_state_writer
          command_bus
          reader_launch_service_factory
          download_workflow_factory
          dictionary_workflow_factory
          annotation_workflow_factory
          progress_presenter_factory
          reader_session_context
          menu_session_context
          clock
        ].freeze

        class << self
          def build(**kwargs)
            new(
              core: MenuCoreBundle.new(**slice(kwargs, MENU_CORE_FIELDS)),
              services: MenuServiceBundle.new(
                workflow: MenuWorkflowServiceBundle.new(**slice(kwargs, MENU_SERVICE_WORKFLOW_FIELDS)),
                domain: MenuDomainServiceBundle.new(**slice(kwargs, MENU_SERVICE_DOMAIN_FIELDS)),
                reader_runtime: MenuReaderServiceBundle.new(**slice(kwargs, MENU_SERVICE_READER_RUNTIME_FIELDS))
              ),
              session: MenuSessionBundle.new(**slice(kwargs, MENU_SESSION_FIELDS)),
              platform: MenuPlatformBundle.new(**slice(kwargs, MENU_PLATFORM_FIELDS))
            )
          end

          private

          def slice(values, keys)
            keys.to_h { |key| [key, values[key]] }
          end
        end

        MENU_CORE_FIELDS.each do |field|
          define_method(field) { core.public_send(field) }
        end

        MENU_SERVICE_WORKFLOW_FIELDS.each do |field|
          define_method(field) { services.workflow.public_send(field) }
        end

        MENU_SERVICE_DOMAIN_FIELDS.each do |field|
          define_method(field) { services.domain.public_send(field) }
        end

        MENU_SERVICE_READER_RUNTIME_FIELDS.each do |field|
          define_method(field) { services.reader_runtime.public_send(field) }
        end

        MENU_SESSION_FIELDS.each do |field|
          define_method(field) { session.public_send(field) }
        end

        MENU_PLATFORM_FIELDS.each do |field|
          define_method(field) { platform.public_send(field) }
        end

        def validate!
          missing = MENU_REQUIRED_FIELDS.select { |field| public_send(field).nil? }
          return self if missing.empty?

          raise ArgumentError, "Missing required menu dependencies: #{missing.join(', ')}"
        end
      end
    end
  end
end
