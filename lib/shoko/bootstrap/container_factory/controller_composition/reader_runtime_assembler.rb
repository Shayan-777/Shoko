# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        # Assembles runtime components for reader controller composition.
        module ReaderRuntimeAssembler
          RuntimeContext = Struct.new(
            :doc,
            :terminal_service,
            :page_calculator,
            :layout_service,
            :ui_state_reader,
            :sidebar_state_reader,
            :config_reader,
            :reader_state_reader,
            :state_writer,
            :command_bus,
            :input_system_factory,
            :rendering_factory,
            :observer_registry,
            :progress_repository,
            :bookmark_repository,
            :annotation_service,
            :logger,
            :navigation_service,
            :bookmark_service,
            :coordinate_service,
            :notification_service,
            :pagination_cache,
            :notification_writer,
            :async_executor,
            :display_capabilities,
            :instrumentation,
            :process_control,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :layout_metrics,
            :rendered_content_reader,
            :selection_service,
            :ui_component_factory,
            :in_book_search_service,
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :annotation_overlay_ui_session,
            :clock,
            :formatting_service,
            :wrapping_service,
            :reader_ui_dependencies
          )

          module_function

          def call(controller:, context:)
            frame_coordinator = context.rendering_factory.create_frame_coordinator(
              terminal_service: context.terminal_service,
              state_writer: context.state_writer,
              ui_state_reader: context.ui_state_reader
            )
            render_pipeline = context.rendering_factory.create_render_pipeline(
              reader_state_reader: context.reader_state_reader,
              logger: context.logger
            )

            pagination_coordinator = Shoko::Application::Services::Pagination::PaginationCoordinator.new(
              doc: context.doc,
              page_calculator: context.page_calculator,
              layout_service: context.layout_service,
              ui_state_reader: context.ui_state_reader,
              pagination_cache: context.pagination_cache,
              notification_writer: context.notification_writer,
              logger: context.logger,
              reader_render_requester: Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge.new(
                controller: controller,
                logger: context.logger
              ),
              async_executor: context.async_executor,
              display_capabilities: context.display_capabilities,
              instrumentation: context.instrumentation,
              config_reader: context.config_reader,
              reader_state_reader: context.reader_state_reader,
              pagination_state_writer: context.state_writer,
              ui_loading_writer: context.state_writer,
              sidebar_state_reader: context.sidebar_state_reader
            )

            state_controller = Shoko::Adapters::Input::Controllers::StateController.new(
              deps: Shoko::Adapters::Input::Controllers::StateController::Dependencies.new(
                reader_state: context.reader_state_reader,
                config_reader: context.config_reader,
                ui_state: context.ui_state_reader,
                sidebar_state: context.sidebar_state_reader,
                state_writer: context.state_writer,
                rendered_content_reader: context.rendered_content_reader,
                doc: context.doc,
                path: controller.path,
                terminal_service: context.terminal_service,
                progress_repository: context.progress_repository,
                bookmark_repository: context.bookmark_repository,
                annotation_service: context.annotation_service,
                logger: context.logger,
                navigation_service: context.navigation_service,
                page_calculator: context.page_calculator,
                layout_service: context.layout_service,
                bookmark_service: context.bookmark_service,
                notification_service: context.notification_service,
                coordinate_service: context.coordinate_service,
                process_control: context.process_control
              ).validate!
            )

            ui_controller = nil
            input_controller = context.input_system_factory.create_reader_input_controller(
              reader_state_reader: context.reader_state_reader,
              state_writer: context.state_writer,
              command_bus: context.command_bus,
              ui_controller_provider: -> { ui_controller }
            )

            sidebar_controller = Shoko::Adapters::Input::Controllers::SidebarController.new(
              deps: Shoko::Adapters::Input::Controllers::SidebarController::Dependencies.new(
                reader_state: context.reader_state_reader,
                config_reader: context.config_reader,
                state_writer: context.state_writer,
                sidebar_state: context.sidebar_state_reader,
                ui_state: context.ui_state_reader,
                document: context.doc,
                navigation_service: context.navigation_service,
                bookmark_service: context.bookmark_service,
                state_controller: state_controller,
                ui_controller: nil,
                notification_service: context.notification_service,
                formatting_service: context.formatting_service,
                layout_service: context.layout_service
              ).validate!
            )

            dictionary_controller = Shoko::Adapters::Input::Controllers::DictionaryController.new(
              deps: Shoko::Adapters::Input::Controllers::DictionaryController::Dependencies.new(
                reader_state: context.reader_state_reader,
                config_reader: context.config_reader,
                sidebar_state: context.sidebar_state_reader,
                state_writer: context.state_writer,
                layout_metrics: context.layout_metrics,
                dictionary_service: context.dictionary_service,
                dictionary_catalog_service: context.dictionary_catalog_service,
                terminal_service: context.terminal_service,
                ui_component_factory: context.ui_component_factory,
                logger: context.logger,
                input_controller: input_controller,
                layout_service: context.layout_service,
                reader_controller: controller,
                document: context.doc,
                selection_service: context.selection_service,
                rendered_content_reader: context.rendered_content_reader,
                notification_service: context.notification_service,
                settings_service: context.settings_service,
                dictionary_availability: context.dictionary_availability,
                dictionary_storage: context.dictionary_storage,
                dictionary_ui_session: context.dictionary_ui_session,
                ui_controller: nil,
                clock: context.clock
              ).validate!
            )

            annotation_controller = Shoko::Adapters::Input::Controllers::AnnotationOverlayController.new(
              reader_state: context.reader_state_reader,
              state_writer: context.state_writer,
              ui_component_factory: context.ui_component_factory,
              state_controller: state_controller,
              reader_controller: controller,
              input_controller: input_controller,
              annotation_service: context.annotation_service,
              annotation_overlay_ui_session: context.annotation_overlay_ui_session,
              notification_service: context.notification_service,
              logger: context.logger
            )

            in_book_search_controller = Shoko::Adapters::Input::Controllers::InBookSearchController.new(
              reader_state: context.reader_state_reader,
              state_writer: context.state_writer,
              search_service: context.in_book_search_service,
              input_controller: input_controller,
              reader_controller: controller,
              state_controller: state_controller,
              in_book_search_ui_session: context.in_book_search_ui_session,
              notification_service: context.notification_service,
              logger: context.logger
            )

            ui_controller = Shoko::Adapters::Input::Controllers::UIController.new(
              deps: Shoko::Adapters::Input::Controllers::UIController::Dependencies.new(
                reader_state: context.reader_state_reader,
                config_reader: context.config_reader,
                state_writer: context.state_writer,
                sidebar_state: context.sidebar_state_reader,
                ui_state: context.ui_state_reader,
                sidebar_controller: sidebar_controller,
                dictionary_controller: dictionary_controller,
                annotation_controller: annotation_controller,
                in_book_search_controller: in_book_search_controller,
                input_controller: input_controller,
                reader_controller: controller,
                notification_service: context.notification_service,
                selection_service: context.selection_service,
                rendered_content_reader: context.rendered_content_reader,
                clipboard_service: controller.clipboard_service,
                ui_component_factory: context.ui_component_factory,
                annotation_service: context.annotation_service,
                logger: context.logger
              ).validate!
            )

            render_dependencies = {
              controller: controller,
              observer_registry: context.observer_registry,
              ui_state_reader: context.ui_state_reader,
              terminal_service: context.terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              ui_controller: ui_controller,
              wrapping_service: context.wrapping_service,
              pagination: pagination_coordinator,
              doc: context.doc,
              reader_dependencies: context.reader_ui_dependencies,
              coordinate_service: context.coordinate_service,
              notification_service: context.notification_service,
              logger: context.logger,
              render_state_writer: context.reader_ui_dependencies&.render_state_writer,
              config_reader: context.config_reader,
              view_model_builder_factory: context.reader_ui_dependencies&.view_model_builder_factory,
              reader_state_reader: context.reader_state_reader,
            }
            render_coordinator = context.rendering_factory.create_reader_render_coordinator(
              reader_dependencies: render_dependencies
            )

            context.observer_registry.add_observer(
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
        end
      end
    end
  end
end
