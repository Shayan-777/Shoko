# frozen_string_literal: true

require_relative 'runtime_bootstrap_dependencies'

module Shoko
  module Adapters
    module Input
      module Controllers
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
              :command_bus,
              :pagination_coordinator_factory
            )

            ReaderWorkflowServiceBundle = Data.define(
              :instrumentation,
              :navigation_service,
              :bookmark_service,
              :in_book_search_service,
              :key_classifier,
              :selection_service,
              :coordinate_service,
              :document_path_resolver,
              :popup_position_service,
              :pending_jump_handler_factory
            )

            ReaderRenderingServiceBundle = Data.define(
              :wrapping_service,
              :rendered_content_reader,
              :annotation_service,
              :render_registry,
              :document_service_factory,
              :notification_service,
              :ui_component_factory,
              :layout_metrics,
              :runtime_config,
              :formatting_service,
              :reader_ui_dependencies
            )

            ReaderSupportServiceBundle = Data.define(
              :dictionary_service,
              :dictionary_catalog_service,
              :settings_service,
              :dictionary_availability,
              :dictionary_storage,
              :cache_pointer_resolver,
              :path_ops
            )

            ReaderServiceBundle = Data.define(
              :workflow,
              :rendering,
              :support
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
              :reader_lifecycle_factory,
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
              :clock,
              :process_control
            )

            ReaderStateFacade = Data.define(
              :reader_state_reader,
              :state_writer,
              :ui_state_reader,
              :sidebar_state_reader,
              :config_reader
            )

            ReaderWorkflowFacade = Data.define(
              :navigation_service,
              :bookmark_service,
              :in_book_search_service,
              :selection_service,
              :coordinate_service,
              :document_path_resolver,
              :popup_position_service,
              :pending_jump_handler_factory
            )

            ReaderRenderingFacade = Data.define(
              :wrapping_service,
              :rendered_content_reader,
              :annotation_service,
              :render_registry,
              :document_service_factory,
              :notification_service,
              :ui_component_factory,
              :layout_metrics,
              :runtime_config,
              :formatting_service,
              :reader_ui_dependencies
            )

            ReaderLifecycleFacade = Data.define(
              :reader_lifecycle_factory,
              :background_worker,
              :background_worker_factory,
              :async_executor,
              :instrumentation_service,
              :pagination_cache_preloader
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
              command_bus
              pagination_coordinator_factory
            ].freeze

            READER_SERVICE_WORKFLOW_FIELDS = %i[
              instrumentation
              navigation_service
              bookmark_service
              in_book_search_service
              key_classifier
              selection_service
              coordinate_service
              document_path_resolver
              popup_position_service
              pending_jump_handler_factory
            ].freeze

            READER_SERVICE_RENDERING_FIELDS = %i[
              wrapping_service
              rendered_content_reader
              annotation_service
              render_registry
              document_service_factory
              notification_service
              ui_component_factory
              layout_metrics
              runtime_config
              formatting_service
              reader_ui_dependencies
            ].freeze

            READER_SERVICE_SUPPORT_FIELDS = %i[
              dictionary_service
              dictionary_catalog_service
              settings_service
              dictionary_availability
              dictionary_storage
              cache_pointer_resolver
              path_ops
            ].freeze

            READER_SERVICE_FIELDS = (
              READER_SERVICE_WORKFLOW_FIELDS +
              READER_SERVICE_RENDERING_FIELDS +
              READER_SERVICE_SUPPORT_FIELDS
            ).freeze

            READER_SESSION_FIELDS = %i[
              dictionary_ui_session
              in_book_search_ui_session
              annotation_overlay_ui_session
              reader_ui_dependencies
              reader_session_context
            ].freeze

            READER_RUNTIME_FIELDS = %i[
              background_worker
              reader_lifecycle_factory
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
              command_bus
              pagination_coordinator_factory
              in_book_search_service
              pending_jump_handler_factory
              reader_lifecycle_factory
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
                  services: ReaderServiceBundle.new(
                    workflow: ReaderWorkflowServiceBundle.new(**slice(kwargs, READER_SERVICE_WORKFLOW_FIELDS)),
                    rendering: ReaderRenderingServiceBundle.new(**slice(kwargs, READER_SERVICE_RENDERING_FIELDS)),
                    support: ReaderSupportServiceBundle.new(**slice(kwargs, READER_SERVICE_SUPPORT_FIELDS))
                  ),
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

            READER_SERVICE_WORKFLOW_FIELDS.each do |field|
              define_method(field) { services.workflow.public_send(field) }
            end

            READER_SERVICE_RENDERING_FIELDS.each do |field|
              define_method(field) { services.rendering.public_send(field) }
            end

            READER_SERVICE_SUPPORT_FIELDS.each do |field|
              define_method(field) { services.support.public_send(field) }
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

            def state_facade
              ReaderStateFacade.new(
                reader_state_reader: reader_state_reader,
                state_writer: state_writer,
                ui_state_reader: ui_state_reader,
                sidebar_state_reader: sidebar_state_reader,
                config_reader: config_reader
              )
            end

            def workflow_facade
              ReaderWorkflowFacade.new(
                navigation_service: navigation_service,
                bookmark_service: bookmark_service,
                in_book_search_service: in_book_search_service,
                selection_service: selection_service,
                coordinate_service: coordinate_service,
                document_path_resolver: document_path_resolver,
                popup_position_service: popup_position_service,
                pending_jump_handler_factory: pending_jump_handler_factory
              )
            end

            def rendering_facade
              ReaderRenderingFacade.new(
                wrapping_service: wrapping_service,
                rendered_content_reader: rendered_content_reader,
                annotation_service: annotation_service,
                render_registry: render_registry,
                document_service_factory: document_service_factory,
                notification_service: notification_service,
                ui_component_factory: ui_component_factory,
                layout_metrics: layout_metrics,
                runtime_config: runtime_config,
                formatting_service: formatting_service,
                reader_ui_dependencies: reader_ui_dependencies
              )
            end

            def lifecycle_facade
              ReaderLifecycleFacade.new(
                reader_lifecycle_factory: reader_lifecycle_factory,
                background_worker: background_worker,
                background_worker_factory: background_worker_factory,
                async_executor: async_executor,
                instrumentation_service: instrumentation_service,
                pagination_cache_preloader: pagination_cache_preloader
              )
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
                command_bus: command_bus,
                pagination_coordinator_factory: pagination_coordinator_factory,
                logger: logger,
                clock: clock,
                process_control: process_control
              )
            end
          end
        end
      end
    end
  end
end
