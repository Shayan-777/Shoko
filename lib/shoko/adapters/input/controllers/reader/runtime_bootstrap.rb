# frozen_string_literal: true

require_relative '../../dependencies/runtime_bootstrap_dependencies'
require_relative '../../services/pagination/pagination_coordinator'

module Shoko
  module Application
    module Controllers
      module Reader
        # Builds the runtime controller/coordinator graph for a reader session.
        class RuntimeBootstrap
          Bootstrap = Struct.new(:ui_controller, :state_controller, :input_controller,
                                 :pagination_coordinator, :render_coordinator, keyword_init: true)

          def initialize(deps:)
            deps.validate!

            @observer_registry = deps.observer_registry
            @doc = deps.doc
            @terminal_service = deps.terminal_service
            @page_calculator = deps.page_calculator
            @clipboard_service = deps.clipboard_service
            @layout_service = deps.layout_service
            @rendering_factory = deps.rendering_factory
            @input_system_factory = deps.input_system_factory
            @config_reader = deps.config_reader
            @reader_state_reader = deps.reader_state_reader
            @state_writer = deps.state_writer
            @navigation_service = deps.navigation_service
            @bookmark_service = deps.bookmark_service
            @in_book_search_service = deps.in_book_search_service
            @selection_service = deps.selection_service
            @rendered_content_reader = deps.rendered_content_reader
            @annotation_service = deps.annotation_service
            @render_registry = deps.render_registry
            @coordinate_service = deps.coordinate_service
            @notification_service = deps.notification_service
            @ui_component_factory = deps.ui_component_factory
            @layout_metrics = deps.layout_metrics
            @dictionary_service = deps.dictionary_service
            @dictionary_catalog_service = deps.dictionary_catalog_service
            @settings_service = deps.settings_service
            @dictionary_availability = deps.dictionary_availability
            @dictionary_storage = deps.dictionary_storage
            @runtime_config = deps.runtime_config
            @formatting_service = deps.formatting_service
            @dictionary_ui_session = deps.dictionary_ui_session
            @in_book_search_ui_session = deps.in_book_search_ui_session
            @annotation_overlay_ui_session = deps.annotation_overlay_ui_session
            @progress_repository = deps.progress_repository
            @bookmark_repository = deps.bookmark_repository
            @pagination_cache = deps.pagination_cache
            @notification_writer = deps.notification_writer
            @async_executor = deps.async_executor
            @display_capabilities = deps.display_capabilities
            @instrumentation = deps.instrumentation
            @ui_state_reader = deps.ui_state_reader
            @sidebar_state_reader = deps.sidebar_state_reader
            @reader_ui_dependencies = deps.reader_ui_dependencies
            @wrapping_service = deps.wrapping_service
            @command_port = deps.command_port
            @logger = deps.logger
            @clock = deps.clock
            @process_control = deps.process_control
          end

          def build(reader_controller:)
            ui = UIController.new(
              reader_state: @reader_state_reader,
              config_reader: @config_reader,
              state_writer: @state_writer,
              sidebar_state: @sidebar_state_reader,
              ui_state: @ui_state_reader,
              notification_service: @notification_service,
              selection_service: @selection_service,
              rendered_content_reader: @rendered_content_reader,
              clipboard_service: @clipboard_service,
              ui_component_factory: @ui_component_factory,
              input_controller: nil,
              reader_controller: reader_controller,
              state_controller: nil,
              annotation_service: @annotation_service,
              dictionary_service: @dictionary_service,
              dictionary_catalog_service: @dictionary_catalog_service,
              terminal_service: @terminal_service,
              layout_metrics: @layout_metrics,
              layout_service: @layout_service,
              document: @doc,
              dictionary_ui_session: @dictionary_ui_session,
              in_book_search_ui_session: @in_book_search_ui_session,
              annotation_overlay_ui_session: @annotation_overlay_ui_session,
              in_book_search_service: @in_book_search_service,
              navigation_service: @navigation_service,
              bookmark_service: @bookmark_service,
              render_registry: @render_registry,
              settings_service: @settings_service,
              logger: @logger,
              dictionary_availability: @dictionary_availability,
              dictionary_storage: @dictionary_storage,
              runtime_config: @runtime_config,
              formatting_service: @formatting_service,
              clock: @clock
            )
            sc = StateController.new(
              reader_state: @reader_state_reader,
              config_reader: @config_reader,
              ui_state: @ui_state_reader,
              sidebar_state: @sidebar_state_reader,
              state_writer: @state_writer,
              rendered_content_reader: @rendered_content_reader,
              doc: @doc,
              path: reader_controller.path,
              terminal_service: @terminal_service,
              progress_repository: @progress_repository,
              bookmark_repository: @bookmark_repository,
              annotation_service: @annotation_service,
              logger: @logger,
              navigation_service: @navigation_service,
              page_calculator: @page_calculator,
              layout_service: @layout_service,
              bookmark_service: @bookmark_service,
              notification_service: @notification_service,
              coordinate_service: @coordinate_service,
              process_control: @process_control
            )
            input = @input_system_factory.create_reader_input_controller(
              reader_state_reader: @reader_state_reader,
              state_writer: @state_writer,
              command_port: @command_port,
              ui_controller: ui
            )

            ui.input_controller = input
            ui.state_controller = sc

            frame_coordinator = @rendering_factory.create_frame_coordinator(
              terminal_service: @terminal_service,
              state_writer: @state_writer,
              ui_state_reader: @ui_state_reader
            )
            render_pipeline = @rendering_factory.create_render_pipeline(
              reader_state_reader: @reader_state_reader,
              logger: @logger
            )
            pagination = Application::Services::Pagination::PaginationCoordinator.new(
              doc: @doc,
              page_calculator: @page_calculator,
              layout_service: @layout_service,
              terminal_service: @terminal_service,
              pagination_cache: @pagination_cache,
              frame_coordinator: frame_coordinator,
              notification_writer: @notification_writer,
              logger: @logger,
              render_callback: lambda {
                reader_controller.force_redraw
                reader_controller.draw_screen
              },
              async_executor: @async_executor,
              display_capabilities: @display_capabilities,
              instrumentation: @instrumentation,
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader,
              state_writer: @state_writer
            )
            render_dependencies = {
              controller: reader_controller,
              observer_registry: @observer_registry,
              ui_state_reader: @ui_state_reader,
              terminal_service: @terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              ui_controller: ui,
              wrapping_service: @wrapping_service,
              pagination: pagination,
              doc: @doc,
              reader_dependencies: @reader_ui_dependencies,
              coordinate_service: @coordinate_service,
              notification_service: @notification_service,
              logger: @logger,
              render_state_writer: @reader_ui_dependencies&.render_state_writer,
              config_reader: @config_reader,
              view_model_builder_factory: @reader_ui_dependencies&.view_model_builder_factory,
              reader_state_reader: @reader_state_reader
            }
            render = @rendering_factory.create_reader_render_coordinator(
              reader_dependencies: render_dependencies
            )

            @observer_registry.add_observer(reader_controller, %i[reader sidebar_visible], %i[reader dictionary_visible],
                                           %i[reader dictionary_panel], %i[config theme],
                                           %i[config view_mode], %i[config line_spacing],
                                           %i[config page_numbering_mode],
                                           %i[config kitty_images])

            Bootstrap.new(
              ui_controller: ui,
              state_controller: sc,
              input_controller: input,
              pagination_coordinator: pagination,
              render_coordinator: render
            )
          end
        end
      end
    end
  end
end
