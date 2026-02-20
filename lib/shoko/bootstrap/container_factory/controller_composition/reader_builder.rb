# frozen_string_literal: true

require_relative '../../../core/services/in_book_search_service'
require_relative '../../../application/reader_lifecycle'
require_relative '../../../application/pending_jump_handler'
require_relative '../../../application/services/pagination/pagination_coordinator'

module Shoko
  module Bootstrap
      module ContainerFactory
        module ControllerComposition
          module ReaderBuilder
            # Build a fully-wired MouseableReader controller.
            def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
              c = container
              input_system_factory = c.resolve(:input_system_factory)
              session_context = c.resolve_optional(:reader_session_context)
              document = preloaded_document || current_reader_document(c)
              worker = background_worker || current_background_worker(c)
              terminal_service = c.resolve(:terminal_service)
              page_calculator = c.resolve(:page_calculator)
              clipboard_service = c.resolve(:clipboard_service)
              instrumentation = c.resolve_optional(:instrumentation)
              navigation_service = c.resolve_optional(:navigation_service)
              bookmark_service = c.resolve_optional(:bookmark_service)
              key_classifier = c.resolve_optional(:key_classifier)
              selection_service = c.resolve_optional(:selection_service)
              wrapping_service = c.resolve_optional(:wrapping_service)
              rendered_content_reader = c.resolve_optional(:rendered_content_reader)
              annotation_service = c.resolve_optional(:annotation_service)
              render_registry = c.resolve_optional(:render_registry)
              document_service_factory = c.resolve_optional(:document_service_factory)
              coordinate_service = c.resolve_optional(:coordinate_service)
              popup_position_service = c.resolve_optional(:popup_position_service)
              layout_service = c.resolve(:layout_service)
              rendering_factory = c.resolve(:rendering_factory)
              notification_service = c.resolve_optional(:notification_service)
              ui_component_factory = c.resolve_optional(:ui_component_factory)
              layout_metrics = c.resolve_optional(:layout_metrics)
              dictionary_service = c.resolve_optional(:dictionary_service)
              dictionary_catalog_service = c.resolve_optional(:dictionary_catalog_service)
              settings_service = c.resolve_optional(:settings_service)
              dictionary_availability = c.resolve_optional(:dictionary_availability)
              dictionary_storage = c.resolve_optional(:dictionary_storage)
              runtime_config = c.resolve_optional(:runtime_config)
              formatting_service = c.resolve_optional(:formatting_service)
              cache_pointer_resolver = c.resolve_optional(:cache_pointer_resolver)
              path_ops = c.resolve_optional(:path_ops)
              dictionary_ui_session = c.resolve(:dictionary_ui_session)
              in_book_search_ui_session = c.resolve(:in_book_search_ui_session)
              annotation_overlay_ui_session = c.resolve(:annotation_overlay_ui_session)
              background_worker_factory = c.resolve_optional(:background_worker_factory)
              progress_repository = c.resolve_optional(:progress_repository)
              bookmark_repository = c.resolve_optional(:bookmark_repository)
              pagination_cache = c.resolve_optional(:pagination_cache)
              notification_writer = c.resolve_optional(:notification_writer)
              async_executor = c.resolve_optional(:async_executor)
              display_capabilities = c.resolve_optional(:display_capabilities)
              config_reader = c.resolve(:config_reader)
              reader_state_reader = c.resolve(:reader_state_reader)
              state_writer = c.resolve(:state_writer)
              ui_state_reader = c.resolve(:ui_state_reader)
              sidebar_state_reader = c.resolve(:sidebar_state_reader)
              command_bus = c.resolve(:command_bus)
              clock = c.resolve(:clock)
              process_control = c.resolve_optional(:process_control)
              instrumentation_service = c.resolve_optional(:instrumentation_service)
              pagination_cache_preloader = c.resolve_optional(:pagination_cache_preloader)
              render_state_writer = c.resolve_optional(:render_state_writer)
              logger = c.resolve_optional(:logger)
              view_model_builder_factory = c.resolve_optional(:view_model_builder_factory)
              kitty_image_renderer = c.resolve_optional(:kitty_image_renderer)
              reader_lifecycle_factory = lambda do |controller, **kwargs|
                Shoko::Application::ReaderLifecycle.new(controller, **kwargs)
              end
              pending_jump_handler_factory = lambda do |**kwargs|
                Shoko::Application::PendingJumpHandler.new(
                  nil,
                  kwargs.fetch(:ui_controller),
                  reader_state: kwargs.fetch(:reader_state),
                  state_writer: kwargs.fetch(:state_writer),
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

              observer_registry = c.resolve(:observer_registry)
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
                reader_session_context: session_context,
                document: document,
                annotation_service: annotation_service
              )

              if session_context
                session_context.document = document if document
                session_context.background_worker = worker if worker
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
                document_service_factory: document_service_factory,
                coordinate_service: coordinate_service,
                popup_position_service: popup_position_service,
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
                background_worker: worker,
                reader_lifecycle_factory: reader_lifecycle_factory,
                background_worker_factory: background_worker_factory,
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
                reader_session_context: session_context,
                command_bus: command_bus,
                pagination_coordinator_factory: pagination_coordinator_factory,
                logger: logger,
                clock: clock,
                process_control: process_control
              )

              Shoko::Adapters::Input::Controllers::MouseableReader.new(
                epub_path,
                deps: reader_deps,
                render_state_writer: render_state_writer,
                mouse_handler: input_system_factory.create_mouse_handler
              )
            end
          end
        end
      end
  end
end
