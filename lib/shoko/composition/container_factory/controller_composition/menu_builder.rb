# frozen_string_literal: true

require_relative '../../../shared/lazy_proxy'
require_relative '../../../application/use_cases/menu_intent_handler'
require_relative '../../../adapters/input/controllers/menu/controller'
require_relative '../../../adapters/input/controllers/menu/reader_launch_ports_adapter'
require_relative '../../../adapters/input/controllers/menu/workflow_ports_adapter'
require_relative '../../../adapters/input/controllers/menu/intent_runtime_bridge'
require_relative '../../../adapters/ui/rendering/noop_terminal_state_writer'
require_relative 'menu_state_controller_composer'

module Shoko
  module Composition
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
            reader_runtime_context = lazy_container_service(c, :reader_runtime_context)
            ui_state_reader = reader_runtime_context
            reader_session_store = c.resolve(:reader_session_store)
            reader_state_reader = reader_session_store
            menu_session_store = c.resolve(:menu_session_store)
            menu_state_reader = menu_session_store
            menu_session_mutator = c.resolve(:menu_session_mutator)
            config_reader = c.resolve(:app_config_store)
            app_config_store = c.resolve(:app_config_store)
            logger = c.resolve(:logger)
            catalog_service = c.resolve(:catalog_service)
            dictionary_availability = lazy_container_service(c, :dictionary_availability)
            dictionary_storage = lazy_container_service(c, :dictionary_storage)
            annotation_service = lazy_container_service(c, :annotation_service)
            settings_service = lazy_container_service(c, :settings_service)
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
            pagination_orchestrator = Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/services/pagination/pagination_orchestrator'

              Shoko::Application::Services::Pagination::PaginationOrchestrator.new(
                reader_runtime_context: reader_runtime_context,
                pagination_cache: c.resolve(:pagination_cache),
                instrumentation: c.resolve(:instrumentation),
                logger: logger
              )
            end

            menu_ui_dependencies = Shoko::Adapters::Ui::MenuUiDependencies.new(
              menu_state_reader: menu_state_reader,
              menu_session_mutator: menu_session_mutator,
              reader_state_reader: reader_state_reader,
              sidebar_state_reader: reader_state_reader,
              config_reader: config_reader,
              runtime_config: runtime_config,
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              annotation_service: annotation_service,
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
                  menu_session_store: menu_session_store,
                  app_config_store: app_config_store,
                  menu_mode_control: runtime,
                  menu_browse_inspection: runtime,
                  menu_download_selection: runtime,
                  menu_annotation_control: runtime,
                  application_exit_control: runtime,
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
              settings_service: settings_service,
              annotation_service: annotation_service,
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

          def lazy_container_service(container, service_name)
            Shoko::Shared::LazyProxy.new { container.resolve(service_name) }
          end
          private :lazy_container_service
        end
      end
    end
  end
end
