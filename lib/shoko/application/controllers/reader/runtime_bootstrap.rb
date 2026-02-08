# frozen_string_literal: true

module Shoko
  module Application
    module Controllers
      module Reader
        # Builds the runtime controller/coordinator graph for a reader session.
        class RuntimeBootstrap
          Bootstrap = Struct.new(:ui_controller, :state_controller, :input_controller,
                                 :pagination_coordinator, :render_coordinator, keyword_init: true)

          def initialize(container:, state:, doc:, terminal_service:, page_calculator:, clipboard_service:,
                         layout_service:, rendering_factory:, input_system_factory:, config_reader:,
                         reader_state_reader:, state_writer:, navigation_service:, bookmark_service:,
                         selection_service:, rendered_content_reader:, annotation_service:, render_registry:,
                         coordinate_service:, notification_service:, ui_component_factory:, layout_metrics:,
                         dictionary_service:, dictionary_catalog_service:, settings_service:,
                         dictionary_availability:, formatting_service:, progress_repository:,
                         bookmark_repository:, pagination_cache:, notification_writer:, async_executor:,
                         display_capabilities:, instrumentation:, ui_state_reader:, sidebar_state_reader:,
                         wrapping_service:,
                         logger:)
            @container = container
            @state = state
            @doc = doc
            @terminal_service = terminal_service
            @page_calculator = page_calculator
            @clipboard_service = clipboard_service
            @layout_service = layout_service
            @rendering_factory = rendering_factory
            @input_system_factory = input_system_factory
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @state_writer = state_writer
            @navigation_service = navigation_service
            @bookmark_service = bookmark_service
            @selection_service = selection_service
            @rendered_content_reader = rendered_content_reader
            @annotation_service = annotation_service
            @render_registry = render_registry
            @coordinate_service = coordinate_service
            @notification_service = notification_service
            @ui_component_factory = ui_component_factory
            @layout_metrics = layout_metrics
            @dictionary_service = dictionary_service
            @dictionary_catalog_service = dictionary_catalog_service
            @settings_service = settings_service
            @dictionary_availability = dictionary_availability
            @formatting_service = formatting_service
            @progress_repository = progress_repository
            @bookmark_repository = bookmark_repository
            @pagination_cache = pagination_cache
            @notification_writer = notification_writer
            @async_executor = async_executor
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @ui_state_reader = ui_state_reader
            @sidebar_state_reader = sidebar_state_reader
            @wrapping_service = wrapping_service
            @logger = logger
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
              navigation_service: @navigation_service,
              bookmark_service: @bookmark_service,
              render_registry: @render_registry,
              settings_service: @settings_service,
              logger: @logger,
              dictionary_availability: @dictionary_availability,
              formatting_service: @formatting_service
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
              coordinate_service: @coordinate_service
            )
            input = @input_system_factory.create_reader_input_controller(
              @state,
              @container,
              ui_controller: ui
            )

            ui.input_controller = input
            ui.state_controller = sc

            frame_coordinator = @rendering_factory.create_frame_coordinator(@container)
            render_pipeline = @rendering_factory.create_render_pipeline(@container)
            pagination = Core::Services::Pagination::PaginationCoordinator.new(
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
            render = @rendering_factory.create_reader_render_coordinator(
              dependencies: @container,
              state: @state,
              controller: reader_controller,
              terminal_service: @terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              ui_controller: ui,
              wrapping_service: @wrapping_service,
              pagination: pagination,
              doc: @doc
            )

            @state.add_observer(reader_controller, %i[reader sidebar_visible], %i[reader dictionary_visible],
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
