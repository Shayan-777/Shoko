# frozen_string_literal: true

require 'shoko/shared/lazy_proxy'
require 'shoko/application/use_cases/menu_intent_handler'
require 'shoko/adapters/input/controllers/menu/controller'
require 'shoko/adapters/input/controllers/menu/reader_launch_ports_adapter'
require 'shoko/adapters/input/controllers/menu/workflow_ports_adapter'
require 'shoko/adapters/input/controllers/menu/intent_runtime_bridge'
require 'shoko/adapters/ui/rendering/noop_terminal_state_writer'
require 'shoko/adapters/ui/dependency_sets'
require 'shoko/adapters/ui/state/menu_hit_registry'
require_relative 'menu_state_controller_composer'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Builds the fully wired menu controller and its workflow graph.
        module MenuBuilder
          EAGER_SERVICE_MAP = {
            rendering_factory: :rendering_factory,
            menu_launch_state: :menu_launch_state,
            terminal_service: :terminal_service,
            menu_session_store: :menu_session_store,
            menu_transient_store: :menu_transient_store,
            menu_state_reader: :menu_snapshot_projection,
            menu_session_mutator: :menu_session_mutator,
            app_config_store: :app_config_store,
            logger: :logger,
            catalog_service: :catalog_service,
            runtime_config: :runtime_config,
            file_probe: :file_probe,
            path_ops: :path_ops,
            clock: :clock,
            process_control: :process_control,
            observer_registry: :observer_registry,
            ui_component_factory: :ui_component_factory,
            key_classifier: :key_classifier,
            input_system_factory: :input_system_factory,
            notification_service: :notification_service,
            clipboard_service: :clipboard_service,
            pagination_cache: :pagination_cache,
            instrumentation: :instrumentation,
            text_sanitizer: :text_sanitizer,
          }.freeze

          LAZY_SERVICE_MAP = {
            reader_runtime_context: :reader_runtime_context,
            reader_state_reader: :reader_state_reader,
            dictionary_availability: :dictionary_availability,
            dictionary_storage: :dictionary_storage,
            annotation_service: :annotation_service,
            settings_service: :settings_service,
            translation_service: :translation_service,
            download_service: :download_service,
            dictionary_catalog_service: :dictionary_catalog_service,
            translation_model_store: :translation_model_store,
            translation_model_catalog: :translation_model_catalog,
            cache_pointer_resolver: :cache_pointer_resolver,
            reader_document_locator: :reader_document_locator,
            document_loader: :document_loader,
            background_worker_builder: :background_worker_builder,
            recent_files_repository: :recent_files_repository,
            page_calculator: :page_calculator,
            pagination_cache_preloader: :pagination_cache_preloader,
            rss_reader_service: :rss_reader_service,
          }.freeze

          # Typed menu controller build inputs with lazily-resolved heavy collaborators.
          MenuBuildContext = Data.define(
            :rendering_factory,
            :reader_launch_state,
            :menu_launch_state,
            :terminal_service,
            :reader_runtime_context,
            :reader_session_store,
            :reader_view_state_store,
            :reader_pagination_store,
            :reader_state_reader,
            :menu_session_store,
            :menu_transient_store,
            :menu_state_reader,
            :menu_session_mutator,
            :app_config_store,
            :logger,
            :catalog_service,
            :dictionary_availability,
            :dictionary_storage,
            :annotation_service,
            :settings_service,
            :translation_service,
            :runtime_config,
            :file_probe,
            :path_ops,
            :clock,
            :process_control,
            :observer_registry,
            :ui_component_factory,
            :key_classifier,
            :input_system_factory,
            :notification_service,
            :clipboard_service,
            :pagination_cache,
            :instrumentation,
            :download_service,
            :dictionary_catalog_service,
            :translation_model_store,
            :translation_model_catalog,
            :text_sanitizer,
            :cache_pointer_resolver,
            :reader_document_locator,
            :document_loader,
            :background_worker_builder,
            :recent_files_repository,
            :page_calculator,
            :pagination_cache_preloader,
            :rss_reader_service,
            :menu_hit_registry,
            :document
          ) do
            def self.resolve(container)
              reader_launch_state = container.resolve(:reader_launch_state)

              new(
                **resolve_services(container, EAGER_SERVICE_MAP),
                reader_launch_state: reader_launch_state,
                reader_session_store: container.resolve(:reader_session_store),
                reader_view_state_store: container.resolve(:reader_view_state_store),
                reader_pagination_store: container.resolve(:reader_pagination_store),
                **resolve_lazy_services(container, LAZY_SERVICE_MAP),
                menu_hit_registry: Shoko::Adapters::Ui::State::MenuHitRegistry.new,
                document: reader_launch_state&.preloaded_document
              )
            end

            def menu_ui_dependencies
              Shoko::Adapters::Ui::MenuUiDependencies.new(
                menu_state_reader: menu_state_reader,
                menu_session_mutator: menu_session_mutator,
                reader_state_reader: reader_state_reader,
                config_reader: app_config_store,
                runtime_config: runtime_config,
                dictionary_availability: dictionary_availability,
                dictionary_storage: dictionary_storage,
                annotation_service: annotation_service,
                catalog_service: catalog_service,
                rss_reader_service: rss_reader_service,
                menu_hit_registry: menu_hit_registry,
                reader_launch_state: reader_launch_state,
                document: document
              )
            end

            def self.resolve_services(container, service_map)
              service_map.transform_values { |service| container.resolve(service) }
            end
            private_class_method :resolve_services

            def self.resolve_lazy_services(container, service_map)
              service_map.transform_values { |service| lazy_service(container, service) }
            end
            private_class_method :resolve_lazy_services

            def self.lazy_service(container, service_name)
              Shoko::Shared::LazyProxy.new { container.resolve(service_name) }
            end
            private_class_method :lazy_service
          end

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
              translator_screen: menu.main_menu_component.translator_screen,
              cache_path_validator: menu.state_controller,
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

          def build_composition_context(context)
            MenuStateControllerComposer::CompositionContext.new(
              **menu_state_context(context),
              **runtime_service_context(context),
              **workflow_service_context(context)
            )
          end

          def menu_state_context(context)
            {
              menu_state_reader: context.menu_state_reader,
              menu_session_mutator: context.menu_session_mutator,
              reader_state_reader: context.reader_state_reader,
              app_config_store: context.app_config_store,
              reader_session_store: context.reader_session_store,
              reader_view_state_store: context.reader_view_state_store,
              reader_pagination_store: context.reader_pagination_store,
              menu_session_store: context.menu_session_store,
              menu_transient_store: context.menu_transient_store,
              reader_runtime_context: context.reader_runtime_context,
            }
          end

          def runtime_service_context(context)
            {
              pagination_orchestrator: build_pagination_orchestrator(context),
              catalog_service: context.catalog_service,
              logger: context.logger,
              runtime_config: context.runtime_config,
              file_probe: context.file_probe,
              path_ops: context.path_ops,
              clock: context.clock,
              translation_service: context.translation_service,
              reader_launch_state: context.reader_launch_state,
              menu_launch_state: context.menu_launch_state,
              download_service: context.download_service,
              text_sanitizer: context.text_sanitizer,
            }
          end

          def workflow_service_context(context)
            {
              dictionary_catalog_service: context.dictionary_catalog_service,
              dictionary_storage: context.dictionary_storage,
              translation_model_store: context.translation_model_store,
              translation_model_catalog: context.translation_model_catalog,
              annotation_service: context.annotation_service,
              rss_reader_service: context.rss_reader_service,
              cache_pointer_resolver: context.cache_pointer_resolver,
              reader_document_locator: context.reader_document_locator,
              document_loader: context.document_loader,
              background_worker_builder: context.background_worker_builder,
              recent_files_repository: context.recent_files_repository,
              page_calculator: context.page_calculator,
              pagination_cache_preloader: context.pagination_cache_preloader,
            }
          end

          def build_pagination_orchestrator(context)
            Shoko::Shared::LazyProxy.new do
              require 'shoko/application/services/pagination/pagination_orchestrator'
              Shoko::Application::Services::Pagination::PaginationOrchestrator.new(
                reader_runtime_context: context.reader_runtime_context,
                pagination_cache: context.pagination_cache,
                instrumentation: context.instrumentation,
                logger: context.logger
              )
            end
          end

          def menu_intent_capability_dependencies(runtime)
            {
              menu_browse_inspection: runtime,
              menu_download_selection: runtime,
              menu_annotation_control: runtime,
              menu_translator_control: runtime,
            }
          end

          def menu_intent_workflow_dependencies(menu)
            {
              reader_launch_service: menu.state_controller,
              download_workflow: menu.state_controller,
              dictionary_workflow: menu.state_controller,
              translator_packs_workflow: menu.state_controller,
              translator_workflow: menu.state_controller,
              rss_reader_workflow: menu.state_controller,
              annotation_workflow: menu.state_controller,
            }
          end

          def menu_intent_service_dependencies(menu, context)
            {
              settings_service: menu.settings_service,
              annotation_service: menu.annotation_service,
              catalog: menu.catalog,
              menu_transient_store: context.menu_transient_store,
              logger: context.logger,
            }
          end
        end
      end
    end
  end
end
