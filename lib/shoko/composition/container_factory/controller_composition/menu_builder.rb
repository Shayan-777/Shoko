# frozen_string_literal: true

require_relative '../../../shared/lazy_proxy'
require_relative '../../../application/use_cases/menu_intent_handler'
require_relative '../../../adapters/input/controllers/menu/controller'
require_relative '../../../adapters/input/controllers/menu/reader_launch_ports_adapter'
require_relative '../../../adapters/input/controllers/menu/workflow_ports_adapter'
require_relative '../../../adapters/input/controllers/menu/intent_runtime_bridge'
require_relative '../../../adapters/ui/rendering/noop_terminal_state_writer'
require_relative 'menu_builder/build_context'
require_relative 'menu_state_controller_composer'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module MenuBuilder
          # Build a fully-wired MenuController.
          def build_menu_controller(container)
            context = MenuBuildContext.resolve(container)
            frame_coordinator = build_frame_coordinator(context)
            render_pipeline = build_render_pipeline(context)
            composition_context = build_composition_context(context)
            controller_class = Shoko::Adapters::Input::Controllers::Menu::Controller
            controller_class.new(
              runtime: build_runtime_dependencies(
                controller_class: controller_class,
                context: context,
                frame_coordinator: frame_coordinator,
                render_pipeline: render_pipeline
              ),
              builder: build_builder_dependencies(
                controller_class: controller_class,
                container: container,
                context: context,
                composition_context: composition_context
              ),
              support: build_support_dependencies(controller_class: controller_class, context: context)
            )
          end

          private

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

          def build_composition_context(context)
            pagination_orchestrator = Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/services/pagination/pagination_orchestrator'
              Shoko::Application::Services::Pagination::PaginationOrchestrator.new(
                reader_runtime_context: context.reader_runtime_context,
                pagination_cache: context.pagination_cache,
                instrumentation: context.instrumentation,
                logger: context.logger
              )
            end
            MenuStateControllerComposer::CompositionContext.new(
              context.menu_state_reader,
              context.menu_session_mutator,
              context.reader_state_reader,
              context.app_config_store,
              context.reader_session_store,
              context.menu_session_store,
              context.menu_transient_store,
              context.reader_runtime_context,
              pagination_orchestrator,
              context.catalog_service,
              context.logger,
              context.runtime_config,
              context.file_probe,
              context.path_ops,
              context.clock,
              context.reader_launch_state,
              context.menu_launch_state,
              context.download_service,
              context.text_sanitizer,
              context.dictionary_catalog_service,
              context.dictionary_storage,
              context.annotation_service,
              context.cache_pointer_resolver,
              context.reader_document_locator,
              context.document_loader,
              context.background_worker_builder,
              context.recent_files_repository,
              context.page_calculator,
              context.pagination_cache_preloader
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
              intent_handler_factory: lambda { |menu|
                build_menu_intent_handler(menu: menu, context: context)
              },
              state_controller_factory: lambda { |menu|
                compose_menu_state_controller(
                  container: container,
                  menu: menu,
                  context: composition_context
                )
              }
            )
          end

          def build_support_dependencies(controller_class:, context:)
            controller_class::SupportDependencies.build(
              notification_service: context.notification_service,
              settings_service: context.settings_service,
              annotation_service: context.annotation_service,
              logger: context.logger,
              file_probe: context.file_probe,
              path_ops: context.path_ops
            )
          end

          def build_menu_intent_handler(menu:, context:)
            runtime = Shoko::Adapters::Input::Controllers::Menu::IntentRuntimeBridge.new(
              menu_state_reader: context.menu_state_reader,
              browse_screen: menu.main_menu_component.browse_screen,
              library_screen: menu.main_menu_component.library_screen,
              annotations_screen: menu.main_menu_component.annotations_screen,
              annotation_edit_screen: menu.main_menu_component.annotation_edit_screen,
              cache_path_validator: menu.state_controller,
              input_controller_provider: -> { menu.input_controller },
              exit_handler: ->(code, message) { menu.cleanup_and_exit(code, message) }
            )
            Shoko::Application::UseCases::MenuIntentHandler.new(
              menu_session_store: context.menu_session_store,
              app_config_store: context.app_config_store,
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
              menu_transient_store: context.menu_transient_store,
              logger: context.logger
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
