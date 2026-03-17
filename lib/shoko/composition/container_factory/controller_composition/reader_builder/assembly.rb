# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Central reader assembly flow from container resolution to controller construction.
          module Assembly
            REQUIRED_CONTAINER_KEYS = %i[
              input_system_factory
              terminal_service
              terminal_session
              page_calculator
              clipboard_service
              layout_service
              rendering_factory
              dictionary_ui_session
              in_book_search_ui_session
              annotation_overlay_ui_session
              annotation_editor_launcher
              app_config_store
              reader_session_store
              reader_session_mutator
              reader_runtime_context
              reader_ui_session_registry
              clock
              observer_registry
            ].freeze

            OPTIONAL_CONTAINER_KEYS = %i[
              instrumentation
              navigation_service
              bookmark_service
              key_classifier
              selection_service
              wrapping_service
              rendered_content_reader
              annotation_service
              render_registry
              document_loader
              coordinate_service
              reader_document_locator
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
              cache_pointer_resolver
              path_ops
              background_worker_builder
              progress_repository
              bookmark_repository
              pagination_cache
              notification_writer
              async_executor
              display_capabilities
              process_control
              instrumentation_service
              pagination_cache_preloader
              render_state_writer
              logger
              view_model_builder_factory
              kitty_image_renderer
              image_cache_warmup
            ].freeze

            module_function

            def build_controller(container:, epub_path:, preloaded_document:, background_worker:)
              resolved = resolve_reader_inputs(
                container,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              )
              resolved = prepare_reader_runtime_inputs(resolved)
              reader_ui_dependencies = build_reader_ui_dependencies(resolved)
              sync_reader_launch_state!(resolved)
              reader_deps = build_reader_controller_dependencies(
                resolved,
                reader_ui_dependencies: reader_ui_dependencies
              )
              runtime_context = build_reader_runtime_context(
                resolved,
                reader_ui_dependencies: reader_ui_dependencies
              )

              build_reader_controller_instance(
                epub_path,
                resolved,
                reader_deps,
                runtime_context
              )
            end

            def resolve_reader_inputs(container, preloaded_document:, background_worker:)
              required = resolve_many(container, REQUIRED_CONTAINER_KEYS)
              optional = resolve_many(container, OPTIONAL_CONTAINER_KEYS)
              session_context = container.resolve(:reader_launch_state)
              document = preloaded_document || session_context&.preloaded_document

              {
                session_context: session_context,
                document: document,
                worker: background_worker || session_context&.background_worker,
                input_system_factory: required[:input_system_factory],
                terminal_service: required[:terminal_service],
                terminal_session: required[:terminal_session],
                page_calculator: required[:page_calculator],
                clipboard_service: required[:clipboard_service],
                layout_service: required[:layout_service],
                rendering_factory: required[:rendering_factory],
                dictionary_ui_session: required[:dictionary_ui_session],
                in_book_search_ui_session: required[:in_book_search_ui_session],
                annotation_overlay_ui_session: required[:annotation_overlay_ui_session],
                annotation_editor_launcher: required[:annotation_editor_launcher],
                config_reader: required[:app_config_store],
                app_config_store: required[:app_config_store],
                reader_state_reader: required[:reader_session_store],
                reader_session_store: required[:reader_session_store],
                reader_session_mutator: required[:reader_session_mutator],
                ui_state_reader: required[:reader_runtime_context],
                sidebar_state_reader: required[:reader_session_store],
                reader_runtime_context_port: required[:reader_runtime_context],
                reader_ui_session_registry: required[:reader_ui_session_registry],
                clock: required[:clock],
                observer_registry: required[:observer_registry],
              }.merge(optional)
            end

            def prepare_reader_runtime_inputs(resolved)
              worker = resolved[:worker] || build_background_worker(
                background_worker_builder: resolved[:background_worker_builder],
                logger: resolved[:logger],
                name: 'reader-runtime'
              )

              resolved.merge(
                worker: worker,
                async_executor: prefer_worker_executor(async_executor: resolved[:async_executor], worker: worker),
                reader_lifecycle_factory: build_reader_lifecycle_factory,
                pending_jump_handler_factory: build_pending_jump_handler_factory(resolved[:reader_session_store]),
                pagination_coordinator_factory: build_pagination_coordinator_factory,
                in_book_search_service: build_in_book_search_service(
                  document: resolved[:document],
                  logger: resolved[:logger],
                  page_calculator: resolved[:page_calculator],
                  config_reader: resolved[:config_reader]
                )
              )
            end

            def sync_reader_launch_state!(resolved)
              session_context = resolved[:session_context]
              return unless session_context

              session_context.set_preloaded_document(resolved[:document]) if resolved[:document]
              session_context.set_background_worker(resolved[:worker]) if resolved[:worker]
            end

            def build_reader_ui_dependencies(resolved)
              Shoko::Adapters::Ui::ReaderUiDependencies.new(
                observer_registry: resolved[:observer_registry],
                terminal_service: resolved[:terminal_service],
                ui_state_reader: resolved[:ui_state_reader],
                reader_state_reader: resolved[:reader_state_reader],
                sidebar_state_reader: resolved[:sidebar_state_reader],
                config_reader: resolved[:config_reader],
                render_state_writer: resolved[:render_state_writer],
                rendered_content_reader: resolved[:rendered_content_reader],
                notification_service: resolved[:notification_service],
                logger: resolved[:logger],
                coordinate_service: resolved[:coordinate_service],
                view_model_builder_factory: resolved[:view_model_builder_factory],
                layout_service: resolved[:layout_service],
                layout_metrics: resolved[:layout_metrics],
                page_calculator: resolved[:page_calculator],
                wrapping_service: resolved[:wrapping_service],
                formatting_service: resolved[:formatting_service],
                kitty_image_renderer: resolved[:kitty_image_renderer],
                runtime_config: resolved[:runtime_config],
                reader_launch_state: resolved[:session_context],
                document: resolved[:document],
                annotation_service: resolved[:annotation_service]
              )
            end

            def build_reader_controller_dependencies(resolved, reader_ui_dependencies:)
              deps = Shoko::Adapters::Input::Controllers::Dependencies
              values = resolved.merge(
                intent_handler_factory: build_reader_intent_handler_factory(
                  reader_session_store: resolved[:reader_session_store]
                ),
                background_worker: resolved[:worker],
                reader_launch_state: resolved[:session_context],
                reader_ui_dependencies: reader_ui_dependencies,
                warmup_services: deps::ReaderWarmupServices.new(
                  pagination_cache_preloader: resolved[:pagination_cache_preloader],
                  image_cache_warmup: resolved[:image_cache_warmup],
                  kitty_image_renderer: resolved[:kitty_image_renderer]
                )
              )

              {
                core: deps::ReaderControllerCoreDependencies.build(**values).validate!,
                state: deps::ReaderControllerStateDependencies.build(**values).validate!,
                services: deps::ReaderControllerServiceDependencies.build(**values).validate!,
                runtime_boot: deps::ReaderRuntimeBootDependencies.build(**values).validate!,
                runtime_startup: deps::ReaderRuntimeStartupDependencies.build(**values).validate!,
                mouse_support: deps::MouseableReaderDependencies.build(**values).validate!
              }
            end

            def build_reader_runtime_context(resolved, reader_ui_dependencies:)
              ReaderRuntimeAssembler::RuntimeContext.new(
                platform: ReaderRuntimeAssembler::ReaderPlatformContext.new(
                  doc: resolved[:document],
                  terminal_service: resolved[:terminal_service],
                  terminal_session: resolved[:terminal_session],
                  page_calculator: resolved[:page_calculator],
                  clock: resolved[:clock],
                  process_control: resolved[:process_control],
                  async_executor: resolved[:async_executor],
                  display_capabilities: resolved[:display_capabilities],
                  instrumentation: resolved[:instrumentation],
                  logger: resolved[:logger]
                ),
                state: ReaderRuntimeAssembler::ReaderStateContext.new(
                  reader_session_store: resolved[:reader_session_store],
                  reader_session_mutator: resolved[:reader_session_mutator],
                  app_config_store: resolved[:app_config_store],
                  observer_registry: resolved[:observer_registry],
                  reader_runtime_context: resolved[:reader_runtime_context_port],
                  rendered_content_reader: resolved[:rendered_content_reader],
                  notification_writer: resolved[:notification_writer],
                  reader_ui_session_registry: resolved[:reader_ui_session_registry]
                ),
                ui: ReaderRuntimeAssembler::ReaderUiContext.new(
                  layout_service: resolved[:layout_service],
                  layout_metrics: resolved[:layout_metrics],
                  wrapping_service: resolved[:wrapping_service],
                  formatting_service: resolved[:formatting_service],
                  ui_component_factory: resolved[:ui_component_factory],
                  input_system_factory: resolved[:input_system_factory],
                  rendering_factory: resolved[:rendering_factory],
                  dictionary_ui_session: resolved[:dictionary_ui_session],
                  in_book_search_ui_session: resolved[:in_book_search_ui_session],
                  annotation_overlay_ui_session: resolved[:annotation_overlay_ui_session]
                ),
                services: ReaderRuntimeAssembler::ReaderServiceContext.new(
                  navigation_service: resolved[:navigation_service],
                  bookmark_service: resolved[:bookmark_service],
                  annotation_service: resolved[:annotation_service],
                  coordinate_service: resolved[:coordinate_service],
                  notification_service: resolved[:notification_service],
                  selection_service: resolved[:selection_service],
                  dictionary_service: resolved[:dictionary_service],
                  dictionary_catalog_service: resolved[:dictionary_catalog_service],
                  settings_service: resolved[:settings_service],
                  dictionary_availability: resolved[:dictionary_availability],
                  dictionary_storage: resolved[:dictionary_storage],
                  progress_repository: resolved[:progress_repository],
                  bookmark_repository: resolved[:bookmark_repository],
                  pagination_cache: resolved[:pagination_cache],
                  in_book_search_service: resolved[:in_book_search_service]
                ),
                reader_ui_dependencies: reader_ui_dependencies
              )
            end

            def build_reader_controller_instance(epub_path, resolved, reader_deps, runtime_context)
              Shoko::Adapters::Input::Controllers::MouseableReader.new(
                epub_path,
                core: reader_deps.fetch(:core),
                state: reader_deps.fetch(:state),
                services: reader_deps.fetch(:services),
                runtime_boot: reader_deps.fetch(:runtime_boot),
                runtime_startup: reader_deps.fetch(:runtime_startup),
                mouse_support: reader_deps.fetch(:mouse_support),
                render_state_writer: resolved[:render_state_writer],
                mouse_handler: resolved[:input_system_factory].create_mouse_handler,
                runtime_components_factory: lambda do |controller_instance|
                  ReaderRuntimeAssembler.call(
                    controller: controller_instance,
                    context: runtime_context
                  )
                end
              )
            end

            def resolve_many(container, keys)
              keys.to_h do |key|
                [key, container.resolve(key)]
              end
            end
            private_class_method :resolve_many

            def build_background_worker(background_worker_builder:, logger:, name:)
              return nil unless background_worker_builder

              unless background_worker_builder.is_a?(Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder)
                raise ArgumentError,
                      'background_worker_builder must implement Core::Ports::Outbound::BackgroundWorkerBuilder'
              end

              background_worker_builder.build(logger: logger, name: name)
            end
            private_class_method :build_background_worker

            def prefer_worker_executor(async_executor:, worker:)
              return async_executor unless worker
              return worker if async_executor.nil?
              return worker if inline_executor?(async_executor)

              async_executor
            end
            private_class_method :prefer_worker_executor

            def inline_executor?(executor)
              return false unless executor
              return false unless defined?(Shoko::Core::Services::InlineExecutor)

              executor.is_a?(Shoko::Core::Services::InlineExecutor)
            end
            private_class_method :inline_executor?

            def build_reader_lifecycle_factory
              lambda do |controller, **kwargs|
                Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner.new(controller, **kwargs)
              end
            end
            private_class_method :build_reader_lifecycle_factory

            def build_pending_jump_handler_factory(reader_session_store)
              lambda do |**kwargs|
                Shoko::Application::PendingJumpHandler.new(
                  reader_session_store: reader_session_store,
                  annotation_editor_launcher: kwargs[:annotation_editor_launcher],
                  rendered_content_reader: kwargs[:rendered_content_reader],
                  navigation_service: kwargs[:navigation_service],
                  selection_service: kwargs[:selection_service],
                  coordinate_service: kwargs[:coordinate_service]
                )
              end
            end
            private_class_method :build_pending_jump_handler_factory

            def build_pagination_coordinator_factory
              lambda do |**kwargs|
                Shoko::Application::Services::Pagination::PaginationCoordinator.new(**kwargs)
              end
            end
            private_class_method :build_pagination_coordinator_factory

            def build_in_book_search_service(document:, logger:, page_calculator:, config_reader:)
              Shoko::Core::Services::InBookSearchService.new(
                document: document,
                logger: logger,
                page_calculator: page_calculator,
                config_reader: config_reader
              )
            end
            private_class_method :build_in_book_search_service

            def build_reader_intent_handler_factory(reader_session_store:)
              lambda { |controller|
                runtime = Shoko::Adapters::Input::Controllers::Reader::IntentRuntimeBridge.new(
                  reader_controller: controller
                )
                Shoko::Application::UseCases::ReaderIntentHandler.new(
                  navigation_service: controller.navigation_service,
                  bookmark_service: controller.bookmark_service,
                  reader_session_store: reader_session_store,
                  reader_display_control: runtime,
                  reader_popup_control: runtime,
                  reader_dictionary_control: runtime,
                  reader_search_control: runtime,
                  reader_annotation_editor_control: runtime,
                  reader_lifecycle_control: runtime,
                  application_exit_control: runtime
                )
              }
            end
            private_class_method :build_reader_intent_handler_factory
          end
        end
      end
    end
  end
end
