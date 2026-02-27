# frozen_string_literal: true

require_relative '../dependencies/runtime_bootstrap_dependencies'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Builds the runtime controller/coordinator graph for a reader session.
          class RuntimeBootstrap
            Bootstrap = Struct.new(:ui_controller, :state_controller, :input_controller,
                                   :pagination_coordinator, :render_coordinator, keyword_init: true)

            def initialize(deps:)
              deps.validate!

              @state = deps.state_facade
              @workflow = deps.workflow_facade
              @rendering = deps.rendering_facade
              @session = deps.session_facade
              @persistence = deps.persistence_facade
              @platform = deps.platform
            end

            def build(reader_controller:)
              ui = UIController.new(
                reader_state: @state.reader_state_reader,
                config_reader: @state.config_reader,
                state_writer: @state.state_writer,
                sidebar_state: @state.sidebar_state_reader,
                ui_state: @state.ui_state_reader,
                notification_service: @rendering.notification_service,
                selection_service: @workflow.selection_service,
                rendered_content_reader: @rendering.rendered_content_reader,
                clipboard_service: @state.clipboard_service,
                ui_component_factory: @rendering.ui_component_factory,
                input_controller: nil,
                reader_controller: reader_controller,
                state_controller: nil,
                annotation_service: @rendering.annotation_service,
                dictionary_service: @session.dictionary_service,
                dictionary_catalog_service: @session.dictionary_catalog_service,
                terminal_service: @rendering.terminal_service,
                layout_metrics: @rendering.layout_metrics,
                layout_service: @rendering.layout_service,
                document: @state.doc,
                dictionary_ui_session: @session.dictionary_ui_session,
                in_book_search_ui_session: @session.in_book_search_ui_session,
                annotation_overlay_ui_session: @session.annotation_overlay_ui_session,
                in_book_search_service: @workflow.in_book_search_service,
                navigation_service: @workflow.navigation_service,
                bookmark_service: @workflow.bookmark_service,
                render_registry: @rendering.render_registry,
                settings_service: @session.settings_service,
                logger: @platform.logger,
                dictionary_availability: @session.dictionary_availability,
                dictionary_storage: @session.dictionary_storage,
                runtime_config: @rendering.runtime_config,
                formatting_service: @rendering.formatting_service,
                clock: @platform.clock
              )
              sc = StateController.new(
                deps: StateController::Dependencies.new(
                  reader_state: @state.reader_state_reader,
                  config_reader: @state.config_reader,
                  ui_state: @state.ui_state_reader,
                  sidebar_state: @state.sidebar_state_reader,
                  state_writer: @state.state_writer,
                  rendered_content_reader: @rendering.rendered_content_reader,
                  doc: @state.doc,
                  path: reader_controller.path,
                  terminal_service: @rendering.terminal_service,
                  progress_repository: @persistence.progress_repository,
                  bookmark_repository: @persistence.bookmark_repository,
                  annotation_service: @rendering.annotation_service,
                  logger: @platform.logger,
                  navigation_service: @workflow.navigation_service,
                  page_calculator: @state.page_calculator,
                  layout_service: @rendering.layout_service,
                  bookmark_service: @workflow.bookmark_service,
                  notification_service: @rendering.notification_service,
                  coordinate_service: @workflow.coordinate_service,
                  process_control: @platform.process_control
                ).validate!
              )
              input = @state.input_system_factory.create_reader_input_controller(
                reader_state_reader: @state.reader_state_reader,
                state_writer: @state.state_writer,
                command_bus: @state.command_bus,
                ui_controller: ui
              )

              ui.input_controller = input
              ui.state_controller = sc

              frame_coordinator = @rendering.rendering_factory.create_frame_coordinator(
                terminal_service: @rendering.terminal_service,
                state_writer: @state.state_writer,
                ui_state_reader: @state.ui_state_reader
              )
              render_pipeline = @rendering.rendering_factory.create_render_pipeline(
                reader_state_reader: @state.reader_state_reader,
                logger: @platform.logger
              )
              pagination = build_pagination_coordinator(
                reader_controller: reader_controller
              )
              render_dependencies = {
                controller: reader_controller,
                observer_registry: @rendering.observer_registry,
                ui_state_reader: @state.ui_state_reader,
                terminal_service: @rendering.terminal_service,
                frame_coordinator: frame_coordinator,
                render_pipeline: render_pipeline,
                ui_controller: ui,
                wrapping_service: @rendering.wrapping_service,
                pagination: pagination,
                doc: @state.doc,
                reader_dependencies: @rendering.reader_ui_dependencies,
                coordinate_service: @workflow.coordinate_service,
                notification_service: @rendering.notification_service,
                logger: @platform.logger,
                render_state_writer: @rendering.reader_ui_dependencies&.render_state_writer,
                config_reader: @state.config_reader,
                view_model_builder_factory: @rendering.reader_ui_dependencies&.view_model_builder_factory,
                reader_state_reader: @state.reader_state_reader
              }
              render = @rendering.rendering_factory.create_reader_render_coordinator(
                reader_dependencies: render_dependencies
              )

              @rendering.observer_registry.add_observer(
                reader_controller,
                %i[reader sidebar_visible],
                %i[reader dictionary_visible],
                %i[reader dictionary_panel],
                %i[config theme],
                %i[config view_mode],
                %i[config line_spacing],
                %i[config page_numbering_mode],
                %i[config kitty_images]
              )

              Bootstrap.new(
                ui_controller: ui,
                state_controller: sc,
                input_controller: input,
                pagination_coordinator: pagination,
                render_coordinator: render
              )
            end

            private

            def build_pagination_coordinator(reader_controller:)
              factory = @persistence.pagination_coordinator_factory
              raise ArgumentError, 'pagination_coordinator_factory is required' unless factory.respond_to?(:call)

              factory.call(
                doc: @state.doc,
                page_calculator: @state.page_calculator,
                layout_service: @rendering.layout_service,
                terminal_service: @rendering.terminal_service,
                pagination_cache: @persistence.pagination_cache,
                notification_writer: @persistence.notification_writer,
                logger: @platform.logger,
                render_callback: lambda {
                  reader_controller.force_redraw
                  reader_controller.draw_screen
                },
                async_executor: @persistence.async_executor,
                display_capabilities: @persistence.display_capabilities,
                instrumentation: @persistence.instrumentation,
                config_reader: @state.config_reader,
                reader_state_reader: @state.reader_state_reader,
                state_writer: @state.state_writer
              )
            end
          end
        end
      end
    end
  end
end
