# frozen_string_literal: true

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
            if session_context
              session_context.document = document if document
              session_context.background_worker = worker if worker
            end
            Shoko::Application::Controllers::MouseableReader.new(
              epub_path,
              container: c,
              state: c.resolve(:global_state),
              terminal_service: c.resolve(:terminal_service),
              page_calculator: c.resolve(:page_calculator),
              clipboard_service: c.resolve(:clipboard_service),
              instrumentation: c.resolve_optional(:instrumentation),
              navigation_service: c.resolve_optional(:navigation_service),
              bookmark_service: c.resolve_optional(:bookmark_service),
              key_classifier: c.resolve_optional(:key_classifier),
              selection_service: c.resolve_optional(:selection_service),
              wrapping_service: c.resolve_optional(:wrapping_service),
              rendered_content_reader: c.resolve_optional(:rendered_content_reader),
              annotation_service: c.resolve_optional(:annotation_service),
              render_registry: c.resolve_optional(:render_registry),
              document_service_factory: c.resolve_optional(:document_service_factory),
              coordinate_service: c.resolve_optional(:coordinate_service),
              layout_service: c.resolve(:layout_service),
              rendering_factory: c.resolve(:rendering_factory),
              input_system_factory: input_system_factory,
              notification_service: c.resolve_optional(:notification_service),
              ui_component_factory: c.resolve_optional(:ui_component_factory),
              layout_metrics: c.resolve_optional(:layout_metrics),
              dictionary_service: c.resolve_optional(:dictionary_service),
              dictionary_catalog_service: c.resolve_optional(:dictionary_catalog_service),
              settings_service: c.resolve_optional(:settings_service),
              dictionary_availability: c.resolve_optional(:dictionary_availability),
              formatting_service: c.resolve_optional(:formatting_service),
              background_worker: worker,
              background_worker_factory: c.resolve_optional(:background_worker_factory),
              progress_repository: c.resolve_optional(:progress_repository),
              bookmark_repository: c.resolve_optional(:bookmark_repository),
              pagination_cache: c.resolve_optional(:pagination_cache),
              notification_writer: c.resolve_optional(:notification_writer),
              async_executor: c.resolve_optional(:async_executor),
              display_capabilities: c.resolve_optional(:display_capabilities),
              config_reader: c.resolve(:config_reader),
              reader_state_reader: c.resolve(:reader_state_reader),
              state_writer: c.resolve(:state_writer),
              ui_state_reader: c.resolve(:ui_state_reader),
              sidebar_state_reader: c.resolve(:sidebar_state_reader),
              instrumentation_service: c.resolve_optional(:instrumentation_service),
              pagination_cache_preloader: c.resolve_optional(:pagination_cache_preloader),
              render_state_writer: c.resolve_optional(:render_state_writer),
              mouse_handler: input_system_factory.create_mouse_handler,
              logger: c.resolve_optional(:logger),
              document: document,
              reader_session_context: session_context
            )
          end

          # Build a fully-wired MenuController.
          # This is the sole composition point for the menu.
          def build_menu_controller(container)
            c = container
            rendering_factory = c.resolve(:rendering_factory)
            reader_session_context = c.resolve_optional(:reader_session_context)

            Shoko::Application::Controllers::MenuController.new(
              container: c,
              state: c.resolve(:global_state),
              catalog: c.resolve(:catalog_service),
              terminal_service: c.resolve(:terminal_service),
              frame_coordinator: rendering_factory.create_frame_coordinator(c),
              render_pipeline: rendering_factory.create_render_pipeline(c),
              ui_component_factory: c.resolve(:ui_component_factory),
              key_classifier: c.resolve(:key_classifier),
              input_system_factory: c.resolve(:input_system_factory),
              notification_service: c.resolve_optional(:notification_service),
              settings_service: c.resolve_optional(:settings_service),
              annotation_service: c.resolve_optional(:annotation_service),
              logger: c.resolve_optional(:logger),
              pagination_cache: c.resolve_optional(:pagination_cache),
              display_capabilities: c.resolve_optional(:display_capabilities),
              instrumentation: c.resolve_optional(:instrumentation),
              download_service: c.resolve_optional(:download_service),
              dictionary_catalog_service: c.resolve_optional(:dictionary_catalog_service),
              text_sanitizer: c.resolve_optional(:text_sanitizer),
              background_worker_factory: c.resolve_optional(:background_worker_factory),
              recent_files_repository: c.resolve_optional(:recent_files_repository),
              cache_pointer_resolver: c.resolve_optional(:cache_pointer_resolver),
              dictionary_availability: c.resolve_optional(:dictionary_availability),
              page_calculator: c.resolve_optional(:page_calculator),
              layout_service: c.resolve_optional(:layout_service),
              wrapping_service: c.resolve_optional(:wrapping_service),
              document_service_factory: c.resolve_optional(:document_service_factory),
              config_reader: c.resolve_optional(:config_reader),
              reader_state_reader: c.resolve_optional(:reader_state_reader),
              state_writer: c.resolve_optional(:state_writer),
              pagination_cache_preloader: c.resolve_optional(:pagination_cache_preloader),
              runtime_config: c.resolve_optional(:runtime_config),
              reader_session_context: reader_session_context,
              menu_session_context: c.resolve_optional(:menu_session_context),
              document: reader_session_context&.document || c.resolve_optional(:document),
              menu_state_reader: c.resolve(:menu_state_reader),
              menu_state_writer: c.resolve(:menu_state_writer)
            )
          end
        end
      end
    end
  end
end
