# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module ContainerFactory
        module ControllerComposition
          module MenuBuilder
            # Build a fully-wired MenuController.
            def build_menu_controller(container)
              c = container
              rendering_factory = c.resolve(:rendering_factory)
              reader_session_context = c.resolve_optional(:reader_session_context)
              terminal_service = c.resolve(:terminal_service)
              ui_state_reader = c.resolve(:ui_state_reader)
              reader_state_reader = c.resolve(:reader_state_reader)
              menu_state_reader = c.resolve(:menu_state_reader)
              menu_state_writer = c.resolve(:menu_state_writer)
              state_writer = c.resolve(:state_writer)
              logger = c.resolve_optional(:logger)
              catalog_service = c.resolve(:catalog_service)
              dictionary_availability = c.resolve_optional(:dictionary_availability)
              dictionary_storage = c.resolve_optional(:dictionary_storage)
              runtime_config = c.resolve_optional(:runtime_config)
              file_probe = c.resolve_optional(:file_probe)
              path_ops = c.resolve_optional(:path_ops)
              clock = c.resolve(:clock)
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

              menu_deps = Shoko::Application::Composition::Dependencies::MenuControllerDependencies.build(
                observer_registry: c.resolve(:observer_registry),
                catalog: catalog_service,
                terminal_service: terminal_service,
                frame_coordinator: rendering_factory.create_frame_coordinator(
                  terminal_service: terminal_service,
                  state_writer: state_writer,
                  ui_state_reader: ui_state_reader
                ),
                render_pipeline: rendering_factory.create_render_pipeline(
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
end
