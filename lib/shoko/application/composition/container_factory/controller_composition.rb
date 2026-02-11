# frozen_string_literal: true

require_relative '../../../adapters/output/ui/dependency_sets'
require_relative '../dependencies/reader_controller_dependencies'
require_relative '../dependencies/menu_controller_dependencies'

module Shoko
  module Application
    module Composition
      module ContainerFactory
        # Builds fully-wired application controllers.
        module ControllerComposition
          # Build a fully-wired MouseableReader controller.
          # This is the sole composition point for the reader — all .resolve() calls
          # happen here, and the controller itself never touches the container.
          def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
            c = container
            input_system_factory = c.resolve(:input_system_factory)
            session_context = c.resolve_optional(:reader_session_context)
            document = preloaded_document || current_reader_document(c)
            worker = background_worker || current_background_worker(c)
            global_state = c.resolve(:global_state)
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
            command_port = c.resolve(:command_port)
            file_probe = c.resolve_optional(:file_probe)
            path_ops = c.resolve_optional(:path_ops)
            clock = c.resolve_optional(:clock)
            process_control = c.resolve_optional(:process_control)
            instrumentation_service = c.resolve_optional(:instrumentation_service)
            pagination_cache_preloader = c.resolve_optional(:pagination_cache_preloader)
            render_state_writer = c.resolve_optional(:render_state_writer)
            logger = c.resolve_optional(:logger)
            view_model_builder_factory = c.resolve_optional(:view_model_builder_factory)
            kitty_image_renderer = c.resolve_optional(:kitty_image_renderer)

            reader_ui_dependencies = Shoko::Adapters::Output::Ui::ReaderUiDependencies.new(
              global_state: global_state,
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
              reader_session_context: session_context,
              document: document,
              annotation_service: annotation_service
            )

            if session_context
              session_context.document = document if document
              session_context.background_worker = worker if worker
            end
            reader_deps = Shoko::Application::Composition::Dependencies::ReaderControllerDependencies.new(
              state: global_state,
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
              background_worker: worker,
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
              command_port: command_port,
              logger: logger,
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              process_control: process_control
            )

            Shoko::Application::Controllers::MouseableReader.new(
              epub_path,
              deps: reader_deps,
              render_state_writer: render_state_writer,
              mouse_handler: input_system_factory.create_mouse_handler
            )
          end

          # Build a fully-wired MenuController.
          # This is the sole composition point for the menu.
          def build_menu_controller(container)
            c = container
            rendering_factory = c.resolve(:rendering_factory)
            reader_session_context = c.resolve_optional(:reader_session_context)
            global_state = c.resolve(:global_state)
            terminal_service = c.resolve(:terminal_service)
            ui_state_reader = c.resolve(:ui_state_reader)
            reader_state_reader = c.resolve(:reader_state_reader)
            menu_state_reader = c.resolve(:menu_state_reader)
            menu_state_writer = c.resolve(:menu_state_writer)
            logger = c.resolve_optional(:logger)
            catalog_service = c.resolve(:catalog_service)
            dictionary_availability = c.resolve_optional(:dictionary_availability)
            dictionary_storage = c.resolve_optional(:dictionary_storage)
            runtime_config = c.resolve_optional(:runtime_config)
            file_probe = c.resolve_optional(:file_probe)
            path_ops = c.resolve_optional(:path_ops)
            clock = c.resolve_optional(:clock)
            process_control = c.resolve_optional(:process_control)
            document = reader_session_context&.document || c.resolve_optional(:document)
            menu_ui_dependencies = Shoko::Adapters::Output::Ui::MenuUiDependencies.new(
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              reader_state_reader: reader_state_reader,
              sidebar_state_reader: c.resolve_optional(:sidebar_state_reader),
              config_reader: c.resolve_optional(:config_reader),
              runtime_config: runtime_config,
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              annotation_service: c.resolve_optional(:annotation_service),
              catalog_service: catalog_service,
              reader_session_context: reader_session_context,
              document: document
            )

            menu_deps = Shoko::Application::Composition::Dependencies::MenuControllerDependencies.new(
              state: global_state,
              catalog: catalog_service,
              terminal_service: terminal_service,
              frame_coordinator: rendering_factory.create_frame_coordinator(
                terminal_service: terminal_service,
                global_state: global_state,
                ui_state_reader: ui_state_reader
              ),
              render_pipeline: rendering_factory.create_render_pipeline(
                global_state: global_state,
                reader_state_reader: reader_state_reader,
                logger: logger
              ),
              menu_ui_dependencies: menu_ui_dependencies,
              build_reader_controller: lambda do |reader_path, preloaded_document:, background_worker:|
                build_reader_controller(
                  c,
                  reader_path,
                  preloaded_document: preloaded_document,
                  background_worker: background_worker
                )
              end,
              ui_component_factory: c.resolve(:ui_component_factory),
              key_classifier: c.resolve(:key_classifier),
              input_system_factory: c.resolve(:input_system_factory),
              notification_service: c.resolve_optional(:notification_service),
              settings_service: c.resolve_optional(:settings_service),
              annotation_service: c.resolve_optional(:annotation_service),
              logger: logger,
              pagination_cache: c.resolve_optional(:pagination_cache),
              display_capabilities: c.resolve_optional(:display_capabilities),
              instrumentation: c.resolve_optional(:instrumentation),
              download_service: c.resolve_optional(:download_service),
              dictionary_catalog_service: c.resolve_optional(:dictionary_catalog_service),
              text_sanitizer: c.resolve_optional(:text_sanitizer),
              background_worker_factory: c.resolve_optional(:background_worker_factory),
              recent_files_repository: c.resolve_optional(:recent_files_repository),
              cache_pointer_resolver: c.resolve_optional(:cache_pointer_resolver),
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              page_calculator: c.resolve_optional(:page_calculator),
              layout_service: c.resolve_optional(:layout_service),
              wrapping_service: c.resolve_optional(:wrapping_service),
              document_service_factory: c.resolve_optional(:document_service_factory),
              config_reader: c.resolve_optional(:config_reader),
              reader_state_reader: c.resolve_optional(:reader_state_reader),
              state_writer: c.resolve_optional(:state_writer),
              pagination_cache_preloader: c.resolve_optional(:pagination_cache_preloader),
              runtime_config: runtime_config,
              reader_session_context: reader_session_context,
              menu_session_context: c.resolve_optional(:menu_session_context),
              document: document,
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              command_port: c.resolve(:command_port),
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              process_control: process_control
            )

            Shoko::Application::Controllers::MenuController.new(deps: menu_deps)
          end
        end
      end
    end
  end
end
