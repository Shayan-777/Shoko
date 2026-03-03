# frozen_string_literal: true

require_relative '../../../core/services/in_book_search_service'
require_relative '../../../core/ports/outbound/background_worker_builder'
require_relative '../../../application/pending_jump_handler'
require_relative '../../../application/services/pagination/pagination_coordinator'
require_relative '../../../adapters/input/controllers/reader/lifecycle_runner'
require_relative '../../../adapters/input/controllers/reader/render_requester_bridge'
require_relative '../../../adapters/input/controllers/reader/intent_executor_bridge'
require_relative '../../../adapters/input/controllers/ui_controller'
require_relative '../../../adapters/input/controllers/state_controller'
require_relative '../../../adapters/input/controllers/sidebar_controller'
require_relative '../../../adapters/input/controllers/dictionary_controller'
require_relative '../../../adapters/input/controllers/annotation_overlay_controller'
require_relative '../../../adapters/input/controllers/in_book_search_controller'
require_relative '../../../application/use_cases/intents/reader_intent_handler'

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Build a fully-wired MouseableReader controller.
          def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
            c = container
            required = resolve_many(
              c,
              %i[
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
                config_reader
                reader_state_reader
                state_writer
                ui_state_reader
                sidebar_state_reader
                command_bus
                clock
                observer_registry
              ]
            )
            optional = resolve_many(
              c,
              %i[
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
                document_path_resolver
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
              ]
            )

            input_system_factory = required[:input_system_factory]
            session_context = c.resolve(:reader_launch_state)
            document = preloaded_document || session_context&.preloaded_document
            worker = background_worker || session_context&.background_worker
            terminal_service = required[:terminal_service]
            terminal_session = required[:terminal_session]
            page_calculator = required[:page_calculator]
            clipboard_service = required[:clipboard_service]
            instrumentation = optional[:instrumentation]
            navigation_service = optional[:navigation_service]
            bookmark_service = optional[:bookmark_service]
            key_classifier = optional[:key_classifier]
            selection_service = optional[:selection_service]
            wrapping_service = optional[:wrapping_service]
            rendered_content_reader = optional[:rendered_content_reader]
            annotation_service = optional[:annotation_service]
            render_registry = optional[:render_registry]
            document_loader = optional[:document_loader]
            coordinate_service = optional[:coordinate_service]
            document_path_resolver = optional[:document_path_resolver]
            popup_position_service = optional[:popup_position_service]
            layout_service = required[:layout_service]
            rendering_factory = required[:rendering_factory]
            notification_service = optional[:notification_service]
            ui_component_factory = optional[:ui_component_factory]
            layout_metrics = optional[:layout_metrics]
            dictionary_service = optional[:dictionary_service]
            dictionary_catalog_service = optional[:dictionary_catalog_service]
            settings_service = optional[:settings_service]
            dictionary_availability = optional[:dictionary_availability]
            dictionary_storage = optional[:dictionary_storage]
            runtime_config = optional[:runtime_config]
            formatting_service = optional[:formatting_service]
            cache_pointer_resolver = optional[:cache_pointer_resolver]
            path_ops = optional[:path_ops]
            dictionary_ui_session = required[:dictionary_ui_session]
            in_book_search_ui_session = required[:in_book_search_ui_session]
            annotation_overlay_ui_session = required[:annotation_overlay_ui_session]
            annotation_editor_launcher = required[:annotation_editor_launcher]
            background_worker_builder = optional[:background_worker_builder]
            progress_repository = optional[:progress_repository]
            bookmark_repository = optional[:bookmark_repository]
            pagination_cache = optional[:pagination_cache]
            notification_writer = optional[:notification_writer]
            async_executor = optional[:async_executor]
            display_capabilities = optional[:display_capabilities]
            config_reader = required[:config_reader]
            reader_state_reader = required[:reader_state_reader]
            state_writer = required[:state_writer]
            ui_state_reader = required[:ui_state_reader]
            sidebar_state_reader = required[:sidebar_state_reader]
            command_bus = required[:command_bus]
            clock = required[:clock]
            process_control = optional[:process_control]
            instrumentation_service = optional[:instrumentation_service]
            pagination_cache_preloader = optional[:pagination_cache_preloader]
            render_state_writer = optional[:render_state_writer]
            logger = optional[:logger]
            view_model_builder_factory = optional[:view_model_builder_factory]
            kitty_image_renderer = optional[:kitty_image_renderer]
            worker ||= build_background_worker(
              background_worker_builder: background_worker_builder,
              logger: logger,
              name: 'reader-runtime'
            )
            async_executor = prefer_worker_executor(async_executor: async_executor, worker: worker)
            reader_lifecycle_factory = lambda do |controller, **kwargs|
              Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner.new(controller, **kwargs)
            end
            pending_jump_handler_factory = lambda do |**kwargs|
              Shoko::Application::PendingJumpHandler.new(
                reader_state: kwargs.fetch(:reader_state),
                state_writer: kwargs.fetch(:state_writer),
                annotation_editor_launcher: kwargs[:annotation_editor_launcher],
                rendered_content_reader: kwargs[:rendered_content_reader],
                navigation_service: kwargs[:navigation_service],
                selection_service: kwargs[:selection_service],
                coordinate_service: kwargs[:coordinate_service]
              )
            end
            pagination_coordinator_factory = lambda do |**kwargs|
              Shoko::Application::Services::Pagination::PaginationCoordinator.new(**kwargs)
            end
            in_book_search_service = Shoko::Core::Services::InBookSearchService.new(
              document: document,
              logger: logger
            )

            observer_registry = required[:observer_registry]
            reader_ui_dependencies = Shoko::Adapters::Ui::ReaderUiDependencies.new(
              observer_registry: observer_registry,
              terminal_service: terminal_service,
              ui_state_reader: ui_state_reader,
              reader_state_reader: reader_state_reader,
              sidebar_state_reader: sidebar_state_reader,
              config_reader: config_reader,
              render_state_writer: render_state_writer,
              rendered_content_reader: rendered_content_reader,
              notification_service: notification_service,
              logger: logger,
              coordinate_service: coordinate_service,
              view_model_builder_factory: view_model_builder_factory,
              layout_service: layout_service,
              layout_metrics: layout_metrics,
              page_calculator: page_calculator,
              wrapping_service: wrapping_service,
              formatting_service: formatting_service,
              kitty_image_renderer: kitty_image_renderer,
              runtime_config: runtime_config,
              reader_launch_state: session_context,
              document: document,
              annotation_service: annotation_service
            )

            if session_context
              session_context.set_preloaded_document(document) if document
              session_context.set_background_worker(worker) if worker
            end
            reader_deps = Shoko::Adapters::Input::Controllers::Dependencies::ReaderControllerDependencies.build(
              observer_registry: observer_registry,
              terminal_service: terminal_service,
              page_calculator: page_calculator,
              clipboard_service: clipboard_service,
              layout_service: layout_service,
              rendering_factory: rendering_factory,
              input_system_factory: input_system_factory,
              config_reader: config_reader,
              reader_state_reader: reader_state_reader,
              state_writer: state_writer,
              instrumentation: instrumentation,
              navigation_service: navigation_service,
              bookmark_service: bookmark_service,
              key_classifier: key_classifier,
              selection_service: selection_service,
              wrapping_service: wrapping_service,
              rendered_content_reader: rendered_content_reader,
              annotation_service: annotation_service,
              render_registry: render_registry,
              document_loader: document_loader,
              coordinate_service: coordinate_service,
              document_path_resolver: document_path_resolver,
              popup_position_service: popup_position_service,
              annotation_editor_launcher: annotation_editor_launcher,
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
              cache_pointer_resolver: cache_pointer_resolver,
              path_ops: path_ops,
              pending_jump_handler_factory: pending_jump_handler_factory,
              in_book_search_service: in_book_search_service,
              dictionary_ui_session: dictionary_ui_session,
              in_book_search_ui_session: in_book_search_ui_session,
              annotation_overlay_ui_session: annotation_overlay_ui_session,
              terminal_session: terminal_session,
              background_worker: worker,
              reader_lifecycle_factory: reader_lifecycle_factory,
              background_worker_builder: background_worker_builder,
              progress_repository: progress_repository,
              bookmark_repository: bookmark_repository,
              pagination_cache: pagination_cache,
              notification_writer: notification_writer,
              async_executor: async_executor,
              display_capabilities: display_capabilities,
              instrumentation_service: instrumentation_service,
              pagination_cache_preloader: pagination_cache_preloader,
              reader_ui_dependencies: reader_ui_dependencies,
              ui_state_reader: ui_state_reader,
              sidebar_state_reader: sidebar_state_reader,
              document: document,
              reader_launch_state: session_context,
              command_bus: command_bus,
              intent_handler_factory: lambda { |controller|
                intent_executor = Shoko::Adapters::Input::Controllers::Reader::IntentExecutorBridge.new(
                  reader_controller: controller
                )
                Shoko::Application::UseCases::Intents::ReaderIntentHandler.new(
                  deps: Shoko::Application::UseCases::Intents::ReaderIntentHandler::Dependencies.new(
                    intent_executor: intent_executor,
                    command_logger: controller.command_logger
                  )
                )
              },
              pagination_coordinator_factory: pagination_coordinator_factory,
              logger: logger,
              clock: clock,
              process_control: process_control
            )

            controller = Shoko::Adapters::Input::Controllers::MouseableReader.new(
              epub_path,
              deps: reader_deps,
              render_state_writer: render_state_writer,
              mouse_handler: input_system_factory.create_mouse_handler,
              runtime_components_factory: lambda { |controller_instance|
                build_reader_runtime_components(
                  controller: controller_instance,
                  doc: document,
                  terminal_service: terminal_service,
                  page_calculator: page_calculator,
                  layout_service: layout_service,
                  ui_state_reader: ui_state_reader,
                  sidebar_state_reader: sidebar_state_reader,
                  config_reader: config_reader,
                  reader_state_reader: reader_state_reader,
                  state_writer: state_writer,
                  command_bus: command_bus,
                  input_system_factory: input_system_factory,
                  rendering_factory: rendering_factory,
                  observer_registry: observer_registry,
                  progress_repository: progress_repository,
                  bookmark_repository: bookmark_repository,
                  annotation_service: annotation_service,
                  logger: logger,
                  navigation_service: navigation_service,
                  bookmark_service: bookmark_service,
                  coordinate_service: coordinate_service,
                  notification_service: notification_service,
                  pagination_cache: pagination_cache,
                  notification_writer: notification_writer,
                  async_executor: async_executor,
                  display_capabilities: display_capabilities,
                  instrumentation: instrumentation,
                  process_control: process_control,
                  dictionary_service: dictionary_service,
                  dictionary_catalog_service: dictionary_catalog_service,
                  settings_service: settings_service,
                  dictionary_availability: dictionary_availability,
                  dictionary_storage: dictionary_storage,
                  layout_metrics: layout_metrics,
                  rendered_content_reader: rendered_content_reader,
                  selection_service: selection_service,
                  ui_component_factory: ui_component_factory,
                  in_book_search_service: in_book_search_service,
                  dictionary_ui_session: dictionary_ui_session,
                  in_book_search_ui_session: in_book_search_ui_session,
                  annotation_overlay_ui_session: annotation_overlay_ui_session,
                  clock: clock,
                  formatting_service: formatting_service,
                  wrapping_service: wrapping_service,
                  reader_ui_dependencies: reader_ui_dependencies
                )
              }
            )

            controller
          end

          def build_reader_runtime_components(
            controller:,
            doc:,
            terminal_service:,
            page_calculator:,
            layout_service:,
            ui_state_reader:,
            sidebar_state_reader:,
            config_reader:,
            reader_state_reader:,
            state_writer:,
            command_bus:,
            input_system_factory:,
            rendering_factory:,
            observer_registry:,
            progress_repository:,
            bookmark_repository:,
            annotation_service:,
            logger:,
            navigation_service:,
            bookmark_service:,
            coordinate_service:,
            notification_service:,
            pagination_cache:,
            notification_writer:,
            async_executor:,
            display_capabilities:,
            instrumentation:,
            process_control:,
            dictionary_service:,
            dictionary_catalog_service:,
            settings_service:,
            dictionary_availability:,
            dictionary_storage:,
            layout_metrics:,
            rendered_content_reader:,
            selection_service:,
            ui_component_factory:,
            in_book_search_service:,
            dictionary_ui_session:,
            in_book_search_ui_session:,
            annotation_overlay_ui_session:,
            clock:,
            formatting_service:,
            wrapping_service:,
            reader_ui_dependencies:
          )
            frame_coordinator = rendering_factory.create_frame_coordinator(
              terminal_service: terminal_service,
              state_writer: state_writer,
              ui_state_reader: ui_state_reader
            )
            render_pipeline = rendering_factory.create_render_pipeline(
              reader_state_reader: reader_state_reader,
              logger: logger
            )

            pagination_coordinator = Shoko::Application::Services::Pagination::PaginationCoordinator.new(
              doc: doc,
              page_calculator: page_calculator,
              layout_service: layout_service,
              ui_state_reader: ui_state_reader,
              pagination_cache: pagination_cache,
              notification_writer: notification_writer,
              logger: logger,
              reader_render_requester: Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge.new(
                controller: controller,
                logger: logger
              ),
              async_executor: async_executor,
              display_capabilities: display_capabilities,
              instrumentation: instrumentation,
              config_reader: config_reader,
              reader_state_reader: reader_state_reader,
              pagination_state_writer: state_writer,
              ui_loading_writer: state_writer,
              sidebar_state_reader: sidebar_state_reader
            )

            state_controller = Shoko::Adapters::Input::Controllers::StateController.new(
              deps: Shoko::Adapters::Input::Controllers::StateController::Dependencies.new(
                reader_state: reader_state_reader,
                config_reader: config_reader,
                ui_state: ui_state_reader,
                sidebar_state: sidebar_state_reader,
                state_writer: state_writer,
                rendered_content_reader: rendered_content_reader,
                doc: doc,
                path: controller.path,
                terminal_service: terminal_service,
                progress_repository: progress_repository,
                bookmark_repository: bookmark_repository,
                annotation_service: annotation_service,
                logger: logger,
                navigation_service: navigation_service,
                page_calculator: page_calculator,
                layout_service: layout_service,
                bookmark_service: bookmark_service,
                notification_service: notification_service,
                coordinate_service: coordinate_service,
                process_control: process_control
              ).validate!
            )

            ui_controller = nil
            input_controller = input_system_factory.create_reader_input_controller(
              reader_state_reader: reader_state_reader,
              state_writer: state_writer,
              command_bus: command_bus,
              ui_controller_provider: -> { ui_controller }
            )

            sidebar_controller = Shoko::Adapters::Input::Controllers::SidebarController.new(
              deps: Shoko::Adapters::Input::Controllers::SidebarController::Dependencies.new(
                reader_state: reader_state_reader,
                config_reader: config_reader,
                state_writer: state_writer,
                sidebar_state: sidebar_state_reader,
                ui_state: ui_state_reader,
                document: doc,
                navigation_service: navigation_service,
                bookmark_service: bookmark_service,
                state_controller: state_controller,
                ui_controller: nil,
                notification_service: notification_service,
                formatting_service: formatting_service,
                layout_service: layout_service
              ).validate!
            )

            dictionary_controller = Shoko::Adapters::Input::Controllers::DictionaryController.new(
              deps: Shoko::Adapters::Input::Controllers::DictionaryController::Dependencies.new(
                reader_state: reader_state_reader,
                config_reader: config_reader,
                sidebar_state: sidebar_state_reader,
                state_writer: state_writer,
                layout_metrics: layout_metrics,
                dictionary_service: dictionary_service,
                dictionary_catalog_service: dictionary_catalog_service,
                terminal_service: terminal_service,
                ui_component_factory: ui_component_factory,
                logger: logger,
                input_controller: input_controller,
                layout_service: layout_service,
                reader_controller: controller,
                document: doc,
                selection_service: selection_service,
                rendered_content_reader: rendered_content_reader,
                notification_service: notification_service,
                settings_service: settings_service,
                dictionary_availability: dictionary_availability,
                dictionary_storage: dictionary_storage,
                dictionary_ui_session: dictionary_ui_session,
                ui_controller: nil,
                clock: clock
              ).validate!
            )

            annotation_controller = Shoko::Adapters::Input::Controllers::AnnotationOverlayController.new(
              reader_state: reader_state_reader,
              state_writer: state_writer,
              ui_component_factory: ui_component_factory,
              state_controller: state_controller,
              reader_controller: controller,
              input_controller: input_controller,
              annotation_service: annotation_service,
              annotation_overlay_ui_session: annotation_overlay_ui_session,
              notification_service: notification_service,
              logger: logger
            )

            in_book_search_controller = Shoko::Adapters::Input::Controllers::InBookSearchController.new(
              reader_state: reader_state_reader,
              state_writer: state_writer,
              search_service: in_book_search_service,
              input_controller: input_controller,
              reader_controller: controller,
              state_controller: state_controller,
              in_book_search_ui_session: in_book_search_ui_session,
              notification_service: notification_service,
              logger: logger
            )

            ui_controller = Shoko::Adapters::Input::Controllers::UIController.new(
              deps: Shoko::Adapters::Input::Controllers::UIController::Dependencies.new(
                reader_state: reader_state_reader,
                config_reader: config_reader,
                state_writer: state_writer,
                sidebar_state: sidebar_state_reader,
                ui_state: ui_state_reader,
                sidebar_controller: sidebar_controller,
                dictionary_controller: dictionary_controller,
                annotation_controller: annotation_controller,
                in_book_search_controller: in_book_search_controller,
                input_controller: input_controller,
                reader_controller: controller,
                notification_service: notification_service,
                selection_service: selection_service,
                rendered_content_reader: rendered_content_reader,
                clipboard_service: controller.clipboard_service,
                ui_component_factory: ui_component_factory,
                annotation_service: annotation_service,
                logger: logger
              ).validate!
            )

            render_dependencies = {
              controller: controller,
              observer_registry: observer_registry,
              ui_state_reader: ui_state_reader,
              terminal_service: terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              ui_controller: ui_controller,
              wrapping_service: wrapping_service,
              pagination: pagination_coordinator,
              doc: doc,
              reader_dependencies: reader_ui_dependencies,
              coordinate_service: coordinate_service,
              notification_service: notification_service,
              logger: logger,
              render_state_writer: reader_ui_dependencies&.render_state_writer,
              config_reader: config_reader,
              view_model_builder_factory: reader_ui_dependencies&.view_model_builder_factory,
              reader_state_reader: reader_state_reader
            }
            render_coordinator = rendering_factory.create_reader_render_coordinator(
              reader_dependencies: render_dependencies
            )

            observer_registry.add_observer(
              controller,
              %i[reader sidebar_visible],
              %i[reader dictionary_visible],
              %i[reader dictionary_panel],
              %i[config theme],
              %i[config view_mode],
              %i[config line_spacing],
              %i[config page_numbering_mode],
              %i[config kitty_images]
            )

            Shoko::Adapters::Input::Controllers::ReaderController::RuntimeComponents.new(
              ui_controller: ui_controller,
              state_controller: state_controller,
              input_controller: input_controller,
              pagination_coordinator: pagination_coordinator,
              render_coordinator: render_coordinator
            )
          end
          private :build_reader_runtime_components

          def resolve_many(container, keys)
            keys.to_h do |key|
              [key, container.resolve(key)]
            end
          end
          private :resolve_many

          def build_background_worker(background_worker_builder:, logger:, name:)
            return nil unless background_worker_builder
            unless background_worker_builder.is_a?(Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder)
              raise ArgumentError,
                    'background_worker_builder must implement Core::Ports::Outbound::BackgroundWorkerBuilder'
            end

            background_worker_builder.build(logger: logger, name: name)
          end
          private :build_background_worker

          def prefer_worker_executor(async_executor:, worker:)
            return async_executor unless worker
            return worker if async_executor.nil?
            return worker if inline_executor?(async_executor)

            async_executor
          rescue Shoko::Error
            worker
          end
          private :prefer_worker_executor

          def inline_executor?(executor)
            return false unless executor
            return false unless defined?(Shoko::Core::Services::InlineExecutor)

            executor.is_a?(Shoko::Core::Services::InlineExecutor)
          end
          private :inline_executor?
        end
      end
    end
  end
end
