# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module Dependencies
        # Groups MenuController collaborators into bounded bundles.
        MenuControllerDependencies = Data.define(:core, :services, :session, :platform) do
          MenuCoreBundle = Data.define(
            :state,
            :catalog,
            :terminal_service,
            :frame_coordinator,
            :render_pipeline,
            :menu_ui_dependencies,
            :build_reader_controller,
            :ui_component_factory,
            :key_classifier,
            :input_system_factory,
            :menu_state_reader,
            :menu_state_writer,
            :command_port
          )

          MenuServiceBundle = Data.define(
            :notification_service,
            :settings_service,
            :annotation_service,
            :logger,
            :pagination_cache,
            :display_capabilities,
            :instrumentation,
            :download_service,
            :dictionary_catalog_service,
            :text_sanitizer,
            :background_worker_factory,
            :recent_files_repository,
            :cache_pointer_resolver,
            :dictionary_availability,
            :dictionary_storage,
            :page_calculator,
            :layout_service,
            :wrapping_service,
            :document_service_factory,
            :config_reader,
            :reader_state_reader,
            :state_writer,
            :pagination_cache_preloader,
            :runtime_config
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
            state
            catalog
            terminal_service
            frame_coordinator
            render_pipeline
            menu_ui_dependencies
            build_reader_controller
            ui_component_factory
            key_classifier
            input_system_factory
            menu_state_reader
            menu_state_writer
            command_port
          ].freeze

          MENU_SERVICE_FIELDS = %i[
            notification_service
            settings_service
            annotation_service
            logger
            pagination_cache
            display_capabilities
            instrumentation
            download_service
            dictionary_catalog_service
            text_sanitizer
            background_worker_factory
            recent_files_repository
            cache_pointer_resolver
            dictionary_availability
            dictionary_storage
            page_calculator
            layout_service
            wrapping_service
            document_service_factory
            config_reader
            reader_state_reader
            state_writer
            pagination_cache_preloader
            runtime_config
          ].freeze

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
            state
            catalog
            terminal_service
            frame_coordinator
            render_pipeline
            menu_ui_dependencies
            build_reader_controller
            ui_component_factory
            key_classifier
            input_system_factory
            menu_state_reader
            menu_state_writer
            command_port
          ].freeze

          class << self
            def build(**kwargs)
              new(
                core: MenuCoreBundle.new(**slice(kwargs, MENU_CORE_FIELDS)),
                services: MenuServiceBundle.new(**slice(kwargs, MENU_SERVICE_FIELDS)),
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

          MENU_SERVICE_FIELDS.each do |field|
            define_method(field) { services.public_send(field) }
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
end
