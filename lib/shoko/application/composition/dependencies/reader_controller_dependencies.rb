# frozen_string_literal: true

require_relative 'runtime_bootstrap_dependencies'

module Shoko
  module Application
    module Composition
      module Dependencies
        # Groups ReaderController collaborators into bounded bundles.
        ReaderControllerDependencies = Data.define(:core, :services, :sessions, :runtime, :platform) do
          ReaderCoreBundle = Data.define(
            :observer_registry,
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

          ReaderServiceBundle = Data.define(
            :instrumentation,
            :navigation_service,
            :bookmark_service,
            :in_book_search_service,
            :key_classifier,
            :selection_service,
            :wrapping_service,
            :rendered_content_reader,
            :annotation_service,
            :render_registry,
            :document_service_factory,
            :coordinate_service,
            :popup_position_service,
            :notification_service,
            :ui_component_factory,
            :layout_metrics,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :runtime_config,
            :formatting_service
          )

          ReaderSessionBundle = Data.define(
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :annotation_overlay_ui_session,
            :reader_ui_dependencies,
            :reader_session_context
          )

          ReaderRuntimeBundle = Data.define(
            :background_worker,
            :background_worker_factory,
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer,
            :async_executor,
            :display_capabilities,
            :instrumentation_service,
            :pagination_cache_preloader,
            :document
          )

          ReaderPlatformBundle = Data.define(
            :logger,
            :file_probe,
            :path_ops,
            :clock,
            :process_control
          )

          READER_CORE_FIELDS = %i[
            observer_registry
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

          READER_SERVICE_FIELDS = %i[
            instrumentation
            navigation_service
            bookmark_service
            in_book_search_service
            key_classifier
            selection_service
            wrapping_service
            rendered_content_reader
            annotation_service
            render_registry
            document_service_factory
            coordinate_service
            popup_position_service
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
          ].freeze

          READER_SESSION_FIELDS = %i[
            dictionary_ui_session
            in_book_search_ui_session
            annotation_overlay_ui_session
            reader_ui_dependencies
            reader_session_context
          ].freeze

          READER_RUNTIME_FIELDS = %i[
            background_worker
            background_worker_factory
            progress_repository
            bookmark_repository
            pagination_cache
            notification_writer
            async_executor
            display_capabilities
            instrumentation_service
            pagination_cache_preloader
            document
          ].freeze

          READER_PLATFORM_FIELDS = %i[
            logger
            file_probe
            path_ops
            clock
            process_control
          ].freeze

          READER_REQUIRED_FIELDS = %i[
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
            in_book_search_service
            reader_ui_dependencies
            dictionary_ui_session
            in_book_search_ui_session
            annotation_overlay_ui_session
            clock
          ].freeze

          class << self
            def build(**kwargs)
              new(
                core: ReaderCoreBundle.new(**slice(kwargs, READER_CORE_FIELDS)),
                services: ReaderServiceBundle.new(**slice(kwargs, READER_SERVICE_FIELDS)),
                sessions: ReaderSessionBundle.new(**slice(kwargs, READER_SESSION_FIELDS)),
                runtime: ReaderRuntimeBundle.new(**slice(kwargs, READER_RUNTIME_FIELDS)),
                platform: ReaderPlatformBundle.new(**slice(kwargs, READER_PLATFORM_FIELDS))
              )
            end

            private

            def slice(values, keys)
              keys.to_h { |key| [key, values[key]] }
            end
          end

          READER_CORE_FIELDS.each do |field|
            define_method(field) { core.public_send(field) }
          end

          READER_SERVICE_FIELDS.each do |field|
            define_method(field) { services.public_send(field) }
          end

          READER_SESSION_FIELDS.each do |field|
            define_method(field) { sessions.public_send(field) }
          end

          READER_RUNTIME_FIELDS.each do |field|
            define_method(field) { runtime.public_send(field) }
          end

          READER_PLATFORM_FIELDS.each do |field|
            define_method(field) { platform.public_send(field) }
          end

          def validate!
            missing = READER_REQUIRED_FIELDS.select { |field| public_send(field).nil? }
            return self if missing.empty?

            raise ArgumentError, "Missing required reader dependencies: #{missing.join(', ')}"
          end

          def to_runtime_bootstrap_dependencies(doc:)
            RuntimeBootstrapDependencies.build(
              observer_registry: observer_registry,
              doc: doc,
              terminal_service: terminal_service,
              page_calculator: page_calculator,
              clipboard_service: clipboard_service,
              layout_service: layout_service,
              rendering_factory: rendering_factory,
              input_system_factory: input_system_factory,
              config_reader: config_reader,
              reader_state_reader: reader_state_reader,
              state_writer: state_writer,
              navigation_service: navigation_service,
              bookmark_service: bookmark_service,
              in_book_search_service: in_book_search_service,
              selection_service: selection_service,
              rendered_content_reader: rendered_content_reader,
              annotation_service: annotation_service,
              render_registry: render_registry,
              coordinate_service: coordinate_service,
              notification_service: notification_service,
              ui_component_factory: ui_component_factory,
              layout_metrics: layout_metrics,
              dictionary_service: dictionary_service,
              dictionary_catalog_service: dictionary_catalog_service,
              settings_service: settings_service,
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              runtime_config: runtime_config,
              formatting_service: formatting_service,
              dictionary_ui_session: dictionary_ui_session,
              in_book_search_ui_session: in_book_search_ui_session,
              annotation_overlay_ui_session: annotation_overlay_ui_session,
              progress_repository: progress_repository,
              bookmark_repository: bookmark_repository,
              pagination_cache: pagination_cache,
              notification_writer: notification_writer,
              async_executor: async_executor,
              display_capabilities: display_capabilities,
              instrumentation: instrumentation,
              ui_state_reader: ui_state_reader,
              sidebar_state_reader: sidebar_state_reader,
              reader_ui_dependencies: reader_ui_dependencies,
              wrapping_service: wrapping_service,
              command_port: command_port,
              logger: logger,
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              process_control: process_control
            )
          end
        end
      end
    end
  end
end
