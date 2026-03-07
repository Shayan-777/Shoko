# frozen_string_literal: true

require_relative '../../../application/workflows/menu/menu_progress_presenter'
require_relative '../../../application/workflows/menu/null_progress_presenter'
require_relative '../../../application/workflows/menu/reader_launch_service'
require_relative '../../../application/workflows/menu/reader_launch/path_resolution'
require_relative '../../../application/workflows/menu/reader_launch/document_preparation'
require_relative '../../../application/workflows/menu/reader_launch/runtime_execution'
require_relative '../../../application/workflows/menu/reader_launch/progress_orchestration'
require_relative '../../../application/workflows/menu/download_workflow'
require_relative '../../../application/workflows/menu/dictionary_workflow'
require_relative '../../../application/workflows/menu/annotation_workflow'
require_relative '../../../adapters/input/controllers/menu/reader_launch_bridges'
require_relative '../../../adapters/input/controllers/menu/menu_workflow_bridges'
require_relative 'menu_state_controller_composer'

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module MenuBuilder
          # Build a fully-wired MenuController.
          def build_menu_controller(container)
            c = container
            rendering_factory = c.resolve(:rendering_factory)
            reader_launch_state = c.resolve(:reader_launch_state)
            menu_launch_state = c.resolve(:menu_launch_state)
            terminal_service = c.resolve(:terminal_service)
            ui_state_reader = c.resolve(:ui_state_reader)
            reader_state_reader = c.resolve(:reader_state_reader)
            menu_state_reader = c.resolve(:menu_state_reader)
            menu_state_writer = c.resolve(:menu_state_writer)
            state_writer = c.resolve(:state_writer)
            logger = c.resolve(:logger)
            catalog_service = c.resolve(:catalog_service)
            dictionary_availability = c.resolve(:dictionary_availability)
            dictionary_storage = c.resolve(:dictionary_storage)
            runtime_config = c.resolve(:runtime_config)
            file_probe = c.resolve(:file_probe)
            path_ops = c.resolve(:path_ops)
            clock = c.resolve(:clock)
            process_control = c.resolve(:process_control)
            document = reader_launch_state&.preloaded_document

            frame_coordinator = rendering_factory.create_frame_coordinator(
              terminal_service: terminal_service,
              state_writer: state_writer,
              ui_state_reader: ui_state_reader
            )
            render_pipeline = rendering_factory.create_render_pipeline(
              reader_state_reader: reader_state_reader,
              logger: logger
            )
            pagination_orchestrator = Shoko::Application::Services::Pagination::PaginationOrchestrator.new(
              ui_state_reader: ui_state_reader,
              pagination_cache: c.resolve(:pagination_cache),
              display_capabilities: c.resolve(:display_capabilities),
              instrumentation: c.resolve(:instrumentation),
              logger: logger
            )

            menu_ui_dependencies = Shoko::Adapters::Ui::MenuUiDependencies.new(
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              reader_state_reader: reader_state_reader,
              sidebar_state_reader: c.resolve(:sidebar_state_reader),
              config_reader: c.resolve(:config_reader),
              runtime_config: runtime_config,
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              annotation_service: c.resolve(:annotation_service),
              catalog_service: catalog_service,
              reader_launch_state: reader_launch_state,
              document: document
            )

            composition_context = MenuStateControllerComposer::CompositionContext.new(
              container: c,
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              reader_state_reader: reader_state_reader,
              state_writer: state_writer,
              pagination_orchestrator: pagination_orchestrator,
              catalog_service: catalog_service,
              logger: logger,
              runtime_config: runtime_config,
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              reader_launch_state: reader_launch_state,
              menu_launch_state: menu_launch_state
            )

            state_controller_factory = lambda do |menu|
              compose_menu_state_controller(
                menu: menu,
                context: composition_context
              )
            end

            menu_deps = Shoko::Adapters::Input::Controllers::Dependencies::MenuControllerDependencies.build(
              observer_registry: c.resolve(:observer_registry),
              catalog: catalog_service,
              terminal_service: terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              menu_ui_dependencies: menu_ui_dependencies,
              ui_component_factory: c.resolve(:ui_component_factory),
              key_classifier: c.resolve(:key_classifier),
              input_system_factory: c.resolve(:input_system_factory),
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              command_bus: c.resolve(:command_bus),
              state_controller_factory: state_controller_factory,
              notification_service: c.resolve(:notification_service),
              settings_service: c.resolve(:settings_service),
              annotation_service: c.resolve(:annotation_service),
              logger: logger,
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              process_control: process_control
            )

            Shoko::Adapters::Input::Controllers::Menu::Controller.new(deps: menu_deps)
          end

          private

          def compose_menu_state_controller(menu:, context:)
            build_reader_controller_lambda = lambda do |reader_path, preloaded_document:, background_worker:|
              build_reader_controller(
                context.container,
                reader_path,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              )
            end

            MenuStateControllerComposer.call(
              menu: menu,
              context: context,
              reader_controller_builder: build_reader_controller_lambda
            )
          end
        end
      end
    end
  end
end
