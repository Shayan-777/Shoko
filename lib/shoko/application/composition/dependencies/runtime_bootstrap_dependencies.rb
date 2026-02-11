# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module Dependencies
        # Groups Reader::RuntimeBootstrap collaborators into bounded bundles.
        RuntimeBootstrapDependencies = Data.define(:core, :services, :storage, :sessions, :platform) do
          RuntimeBootstrapCoreBundle = Data.define(
            :state,
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
            :command_port
          )

          RuntimeBootstrapServiceBundle = Data.define(
            :navigation_service,
            :bookmark_service,
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
            :file_probe,
            :path_ops,
            :clock,
            :process_control
          )

          RUNTIME_CORE_FIELDS = %i[
            state
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
            command_port
          ].freeze

          RUNTIME_SERVICE_FIELDS = %i[
            navigation_service
            bookmark_service
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
            file_probe
            path_ops
            clock
            process_control
          ].freeze

          RUNTIME_REQUIRED_FIELDS = %i[
            state
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
            command_port
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

          def validate!
            missing = RUNTIME_REQUIRED_FIELDS.select { |field| public_send(field).nil? }
            return self if missing.empty?

            raise ArgumentError, "Missing required runtime bootstrap dependencies: #{missing.join(', ')}"
          end
        end
      end
    end
  end
end
