# frozen_string_literal: true

require_relative '../../../shared/lazy_proxy'
require_relative '../../../application/use_cases/menu_intent_handler'
require_relative '../../../adapters/input/controllers/menu/controller'
require_relative '../../../adapters/input/controllers/menu/reader_launch_ports_adapter'
require_relative '../../../adapters/input/controllers/menu/workflow_ports_adapter'
require_relative '../../../adapters/input/controllers/menu/intent_runtime_bridge'
require_relative '../../../adapters/ui/rendering/noop_terminal_state_writer'
require_relative 'menu_builder/build_context'
require_relative 'menu_builder/composition_support'
require_relative 'menu_builder/intent_handler_dependencies'
require_relative 'menu_state_controller_composer'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Builds the fully wired menu controller and its workflow graph.
        module MenuBuilder
          include CompositionSupport
          include IntentHandlerDependencies

          def build_menu_controller(container)
            context = MenuBuildContext.resolve(container)
            controller_class = Shoko::Adapters::Input::Controllers::Menu::Controller
            controller_class.new(
              **menu_controller_dependencies(
                container: container,
                context: context,
                controller_class: controller_class
              )
            )
          end

          private

          def menu_controller_dependencies(container:, context:, controller_class:)
            {
              runtime: build_menu_runtime_dependencies(controller_class: controller_class, context: context),
              builder: build_menu_builder_dependencies(
                controller_class: controller_class,
                container: container,
                context: context
              ),
              support: build_support_dependencies(controller_class: controller_class, context: context),
            }
          end

          def build_menu_runtime_dependencies(controller_class:, context:)
            build_runtime_dependencies(
              controller_class: controller_class,
              context: context,
              frame_coordinator: build_frame_coordinator(context),
              render_pipeline: build_render_pipeline(context)
            )
          end

          def build_menu_builder_dependencies(controller_class:, container:, context:)
            build_builder_dependencies(
              controller_class: controller_class,
              container: container,
              context: context,
              composition_context: build_composition_context(context)
            )
          end

          def build_frame_coordinator(context)
            context.rendering_factory.create_frame_coordinator(
              terminal_service: context.terminal_service,
              terminal_state_writer: Shoko::Adapters::Ui::Rendering::NoopTerminalStateWriter.new,
              ui_state_reader: context.reader_runtime_context
            )
          end

          def build_render_pipeline(context)
            context.rendering_factory.create_render_pipeline(
              reader_state_reader: context.reader_state_reader,
              logger: context.logger
            )
          end

          def build_runtime_dependencies(controller_class:, context:, frame_coordinator:, render_pipeline:)
            controller_class::RuntimeDependencies.build(
              observer_registry: context.observer_registry,
              catalog: context.catalog_service,
              terminal_service: context.terminal_service,
              frame_coordinator: frame_coordinator,
              render_pipeline: render_pipeline,
              menu_state_reader: context.menu_state_reader,
              menu_session_mutator: context.menu_session_mutator,
              clock: context.clock,
              process_control: context.process_control
            )
          end

          def build_builder_dependencies(controller_class:, container:, context:, composition_context:)
            controller_class::BuilderDependencies.build(
              menu_ui_dependencies: context.menu_ui_dependencies,
              ui_component_factory: context.ui_component_factory,
              key_classifier: context.key_classifier,
              input_system_factory: context.input_system_factory,
              intent_handler_factory: build_intent_handler_factory(context),
              state_controller_factory: build_state_controller_factory(
                container: container,
                context: composition_context
              )
            )
          end

          def build_intent_handler_factory(context)
            ->(menu) { build_menu_intent_handler(menu: menu, context: context) }
          end

          def build_state_controller_factory(container:, context:)
            lambda do |menu|
              compose_menu_state_controller(container: container, menu: menu, context: context)
            end
          end

          def build_support_dependencies(controller_class:, context:)
            controller_class::SupportDependencies.build(
              notification_service: context.notification_service,
              clipboard_service: context.clipboard_service,
              settings_service: context.settings_service,
              annotation_service: context.annotation_service,
              logger: context.logger,
              file_probe: context.file_probe,
              path_ops: context.path_ops
            )
          end

          def build_menu_intent_handler(menu:, context:)
            runtime = build_menu_intent_runtime(menu: menu, context: context)
            Shoko::Application::UseCases::MenuIntentHandler.new(
              menu_session_store: context.menu_session_store,
              app_config_store: context.app_config_store,
              menu_mode_control: runtime,
              application_exit_control: runtime,
              **menu_intent_capability_dependencies(runtime),
              **menu_intent_workflow_dependencies(menu),
              **menu_intent_service_dependencies(menu, context)
            )
          end

          def build_menu_intent_runtime(menu:, context:)
            Shoko::Adapters::Input::Controllers::Menu::IntentRuntimeBridge.new(
              menu_state_reader: context.menu_state_reader,
              browse_screen: menu.main_menu_component.browse_screen,
              library_screen: menu.main_menu_component.library_screen,
              annotations_screen: menu.main_menu_component.annotations_screen,
              annotation_edit_screen: menu.main_menu_component.annotation_edit_screen,
              cache_path_validator: menu.state_controller,
              input_controller_provider: -> { menu.input_controller },
              exit_handler: ->(code, message) { menu.cleanup_and_exit(code, message) }
            )
          end

          def compose_menu_state_controller(container:, menu:, context:)
            build_reader_controller_lambda = lambda do |reader_path, preloaded_document:, background_worker:|
              build_reader_controller(
                container,
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
