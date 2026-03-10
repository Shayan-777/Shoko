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
require_relative '../../../application/use_cases/menu_intent_handler'
require_relative '../../../adapters/input/controllers/menu/reader_launch_bridges'
require_relative '../../../adapters/input/controllers/menu/menu_workflow_bridges'
require_relative '../../../adapters/input/controllers/menu/intent_runtime_bridge'
require_relative '../../../adapters/ui/rendering/noop_terminal_state_writer'
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
            ui_state_reader = c.resolve(:reader_ui_state_view)
            reader_state_reader = c.resolve(:reader_session_view)
            menu_state_reader = c.resolve(:menu_session_view)
            menu_session_mutator = c.resolve(:menu_session_mutator)
            config_reader = c.resolve(:config_view)
            app_config_store = c.resolve(:app_config_store)
            reader_session_store = c.resolve(:reader_session_store)
            reader_runtime_context = c.resolve(:reader_runtime_context)
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
              terminal_state_writer: Shoko::Adapters::Ui::Rendering::NoopTerminalStateWriter.new,
              ui_state_reader: ui_state_reader
            )
            render_pipeline = rendering_factory.create_render_pipeline(
              reader_state_reader: reader_state_reader,
              logger: logger
            )
            pagination_orchestrator = Shoko::Application::Services::Pagination::PaginationOrchestrator.new(
              reader_runtime_context: reader_runtime_context,
              pagination_cache: c.resolve(:pagination_cache),
              instrumentation: c.resolve(:instrumentation),
              logger: logger
            )

            menu_ui_dependencies = Shoko::Adapters::Ui::MenuUiDependencies.new(
              menu_state_reader: menu_state_reader,
              menu_session_mutator: menu_session_mutator,
              reader_state_reader: reader_state_reader,
              sidebar_state_reader: reader_state_reader,
              config_reader: config_reader,
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
              menu_session_mutator: menu_session_mutator,
              reader_state_reader: reader_state_reader,
              app_config_store: app_config_store,
              reader_session_store: reader_session_store,
              reader_runtime_context: reader_runtime_context,
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

            controller_class = Shoko::Adapters::Input::Controllers::Menu::Controller
            runtime_deps = controller_class::RuntimeDependencies.build(
              observer_registry: c.resolve(:observer_registry),
              catalog: catalog_service,
              terminal_service: terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              menu_state_reader: menu_state_reader,
              menu_session_mutator: menu_session_mutator,
              clock: clock,
              process_control: process_control
            )
            builder_deps = controller_class::BuilderDependencies.build(
              menu_ui_dependencies: menu_ui_dependencies,
              ui_component_factory: c.resolve(:ui_component_factory),
              key_classifier: c.resolve(:key_classifier),
              input_system_factory: c.resolve(:input_system_factory),
              intent_handler_factory: lambda { |menu|
                runtime = Shoko::Adapters::Input::Controllers::Menu::IntentRuntimeBridge.new(menu: menu)
                Shoko::Application::UseCases::MenuIntentHandler.new(
                  menu_state_reader: menu.menu_state_reader,
                  menu_session_mutator: menu.menu_session_mutator,
                  menu_runtime: runtime,
                  reader_launch_service: menu.state_controller,
                  download_workflow: menu.state_controller,
                  dictionary_workflow: menu.state_controller,
                  annotation_workflow: menu.state_controller,
                  settings_service: menu.settings_service,
                  annotation_service: menu.annotation_service,
                  catalog: menu.catalog,
                  logger: logger
                )
              },
              state_controller_factory: state_controller_factory
            )
            support_deps = controller_class::SupportDependencies.build(
              notification_service: c.resolve(:notification_service),
              settings_service: c.resolve(:settings_service),
              annotation_service: c.resolve(:annotation_service),
              logger: logger,
              file_probe: file_probe,
              path_ops: path_ops
            )

            controller_class.new(
              runtime: runtime_deps,
              builder: builder_deps,
              support: support_deps
            )
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
