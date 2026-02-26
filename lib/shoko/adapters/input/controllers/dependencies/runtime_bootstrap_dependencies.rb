# frozen_string_literal: true

module Shoko
  module Adapters::Input::Controllers
    module Dependencies
        # Groups Reader::RuntimeBootstrap collaborators into bounded bundles.
        RuntimeBootstrapDependencies = Data.define(:core, :services, :storage, :sessions, :platform) do
          RuntimeBootstrapCoreBundle = Data.define(
            :observer_registry,
            :doc,
            :terminal_service,
            :page_calculator,
            :clipboard_service,
            :layout_service,
            :rendering_factory,
            :input_system_factory,
            :config_reader,
            :reader_state_reader,
            :state_writer,
            :ui_state_reader,
            :sidebar_state_reader,
            :command_bus,
            :pagination_coordinator_factory
          )

          RuntimeBootstrapServiceBundle = Data.define(
            :navigation_service,
            :bookmark_service,
            :in_book_search_service,
            :selection_service,
            :rendered_content_reader,
            :annotation_service,
            :render_registry,
            :coordinate_service,
            :notification_service,
            :ui_component_factory,
            :layout_metrics,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :runtime_config,
            :formatting_service,
            :wrapping_service,
            :reader_ui_dependencies
          )

          RuntimeBootstrapStorageBundle = Data.define(
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer,
            :async_executor,
            :display_capabilities,
            :instrumentation
          )

          RuntimeBootstrapSessionBundle = Data.define(
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :annotation_overlay_ui_session
          )

          RuntimeBootstrapPlatformBundle = Data.define(
            :logger,
            :clock,
            :process_control
          )

          RuntimeStateFacade = Data.define(
            :doc,
            :reader_state_reader,
            :state_writer,
            :ui_state_reader,
            :sidebar_state_reader,
            :config_reader,
            :command_bus,
            :input_system_factory,
            :page_calculator,
            :clipboard_service
          )

          RuntimeWorkflowFacade = Data.define(
            :navigation_service,
            :bookmark_service,
            :in_book_search_service,
            :selection_service,
            :coordinate_service
          )

          RuntimeRenderingFacade = Data.define(
            :observer_registry,
            :terminal_service,
            :layout_service,
            :rendering_factory,
            :wrapping_service,
            :rendered_content_reader,
            :annotation_service,
            :render_registry,
            :notification_service,
            :ui_component_factory,
            :layout_metrics,
            :formatting_service,
            :runtime_config,
            :reader_ui_dependencies
          )

          RuntimeSessionFacade = Data.define(
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :annotation_overlay_ui_session
          )

          RuntimePersistenceFacade = Data.define(
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer,
            :async_executor,
            :display_capabilities,
            :instrumentation,
            :pagination_coordinator_factory
          )

          RUNTIME_CORE_FIELDS = %i[
            observer_registry
            doc
            terminal_service
            page_calculator
            clipboard_service
            layout_service
            rendering_factory
            input_system_factory
            config_reader
            reader_state_reader
            state_writer
            ui_state_reader
            sidebar_state_reader
            command_bus
            pagination_coordinator_factory
          ].freeze

          RUNTIME_SERVICE_FIELDS = %i[
            navigation_service
            bookmark_service
            in_book_search_service
            selection_service
            rendered_content_reader
            annotation_service
            render_registry
            coordinate_service
            notification_service
            ui_component_factory
            layout_metrics
            dictionary_service
            dictionary_catalog_service
            settings_service
            dictionary_availability
            dictionary_storage
            runtime_config
            formatting_service
            wrapping_service
            reader_ui_dependencies
          ].freeze

          RUNTIME_STORAGE_FIELDS = %i[
            progress_repository
            bookmark_repository
            pagination_cache
            notification_writer
            async_executor
            display_capabilities
            instrumentation
          ].freeze

          RUNTIME_SESSION_FIELDS = %i[
            dictionary_ui_session
            in_book_search_ui_session
            annotation_overlay_ui_session
          ].freeze

          RUNTIME_PLATFORM_FIELDS = %i[
            logger
            clock
            process_control
          ].freeze

          RUNTIME_REQUIRED_FIELDS = %i[
            observer_registry
            doc
            terminal_service
            page_calculator
            clipboard_service
            layout_service
            rendering_factory
            input_system_factory
            config_reader
            reader_state_reader
            state_writer
            ui_state_reader
            sidebar_state_reader
            command_bus
            pagination_coordinator_factory
            in_book_search_service
            dictionary_ui_session
            in_book_search_ui_session
            annotation_overlay_ui_session
          ].freeze

          class << self
            def build(**kwargs)
              new(
                core: RuntimeBootstrapCoreBundle.new(**slice(kwargs, RUNTIME_CORE_FIELDS)),
                services: RuntimeBootstrapServiceBundle.new(**slice(kwargs, RUNTIME_SERVICE_FIELDS)),
                storage: RuntimeBootstrapStorageBundle.new(**slice(kwargs, RUNTIME_STORAGE_FIELDS)),
                sessions: RuntimeBootstrapSessionBundle.new(**slice(kwargs, RUNTIME_SESSION_FIELDS)),
                platform: RuntimeBootstrapPlatformBundle.new(**slice(kwargs, RUNTIME_PLATFORM_FIELDS))
              )
            end

            private

            def slice(values, keys)
              keys.to_h { |key| [key, values[key]] }
            end
          end

          RUNTIME_CORE_FIELDS.each do |field|
            define_method(field) { core.public_send(field) }
          end

          RUNTIME_SERVICE_FIELDS.each do |field|
            define_method(field) { services.public_send(field) }
          end

          RUNTIME_STORAGE_FIELDS.each do |field|
            define_method(field) { storage.public_send(field) }
          end

          RUNTIME_SESSION_FIELDS.each do |field|
            define_method(field) { sessions.public_send(field) }
          end

          RUNTIME_PLATFORM_FIELDS.each do |field|
            define_method(field) { platform.public_send(field) }
          end

          def state_facade
            RuntimeStateFacade.new(
              doc: doc,
              reader_state_reader: reader_state_reader,
              state_writer: state_writer,
              ui_state_reader: ui_state_reader,
              sidebar_state_reader: sidebar_state_reader,
              config_reader: config_reader,
              command_bus: command_bus,
              input_system_factory: input_system_factory,
              page_calculator: page_calculator,
              clipboard_service: clipboard_service
            )
          end

          def workflow_facade
            RuntimeWorkflowFacade.new(
              navigation_service: navigation_service,
              bookmark_service: bookmark_service,
              in_book_search_service: in_book_search_service,
              selection_service: selection_service,
              coordinate_service: coordinate_service
            )
          end

          def rendering_facade
            RuntimeRenderingFacade.new(
              observer_registry: observer_registry,
              terminal_service: terminal_service,
              layout_service: layout_service,
              rendering_factory: rendering_factory,
              wrapping_service: wrapping_service,
              rendered_content_reader: rendered_content_reader,
              annotation_service: annotation_service,
              render_registry: render_registry,
              notification_service: notification_service,
              ui_component_factory: ui_component_factory,
              layout_metrics: layout_metrics,
              formatting_service: formatting_service,
              runtime_config: runtime_config,
              reader_ui_dependencies: reader_ui_dependencies
            )
          end

          def session_facade
            RuntimeSessionFacade.new(
              dictionary_service: dictionary_service,
              dictionary_catalog_service: dictionary_catalog_service,
              settings_service: settings_service,
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              dictionary_ui_session: dictionary_ui_session,
              in_book_search_ui_session: in_book_search_ui_session,
              annotation_overlay_ui_session: annotation_overlay_ui_session
            )
          end

          def persistence_facade
            RuntimePersistenceFacade.new(
              progress_repository: progress_repository,
              bookmark_repository: bookmark_repository,
              pagination_cache: pagination_cache,
              notification_writer: notification_writer,
              async_executor: async_executor,
              display_capabilities: display_capabilities,
              instrumentation: instrumentation,
              pagination_coordinator_factory: pagination_coordinator_factory
            )
          end

          def validate!
            missing = RUNTIME_REQUIRED_FIELDS.select { |field| public_send(field).nil? }
            return self if missing.empty?

            raise ArgumentError, "Missing required runtime bootstrap dependencies: #{missing.join(', ')}"
          end
        end
      end
  end
end
