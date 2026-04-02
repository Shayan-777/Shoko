# frozen_string_literal: true

require_relative '../../../shared/lazy_proxy'
require_relative 'menu_state_controller_composer/reader_launch_service_factory'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Builds menu state controller and workflow graph for menu composition.
        module MenuStateControllerComposer
          CompositionContext = Data.define(
            :menu_state_reader,
            :menu_session_mutator,
            :reader_state_reader,
            :app_config_store,
            :reader_session_store,
            :reader_view_state_store,
            :reader_pagination_store,
            :menu_session_store,
            :menu_transient_store,
            :reader_runtime_context,
            :pagination_orchestrator,
            :catalog_service,
            :logger,
            :runtime_config,
            :file_probe,
            :path_ops,
            :clock,
            :translation_service,
            :reader_launch_state,
            :menu_launch_state,
            :download_service,
            :text_sanitizer,
            :dictionary_catalog_service,
            :dictionary_storage,
            :annotation_service,
            :cache_pointer_resolver,
            :reader_document_locator,
            :document_loader,
            :background_worker_builder,
            :recent_files_repository,
            :page_calculator,
            :pagination_cache_preloader
          )

          module_function

          def call(menu:, context:, reader_controller_builder:)
            reader_launch_service = build_reader_launch_service(
              menu: menu,
              context: context,
              reader_controller_builder: reader_controller_builder
            )
            workflow_ports = build_workflow_ports(
              menu: menu,
              context: context,
              reader_launch_service: reader_launch_service
            )
            build_state_controller(context: context,
                                   reader_launch_service: reader_launch_service,
                                   workflow_ports: workflow_ports)
          end

          def build_state_controller(context:, reader_launch_service:, workflow_ports:)
            deps = state_controller_deps(
              context: context,
              reader_launch_service: reader_launch_service,
              workflows: build_workflows(context: context, workflow_ports: workflow_ports)
            )
            Shoko::Adapters::Input::Controllers::Menu::StateController.new(deps: deps)
          end
          private_class_method :build_state_controller

          def build_workflow_ports(menu:, context:, reader_launch_service:)
            Shoko::Adapters::Input::Controllers::Menu::WorkflowPortsAdapter.new(
              catalog: context.catalog_service,
              mode_switcher: ->(mode) { menu.switch_to_mode(mode) },
              annotations_screen: menu.main_menu_component.annotations_screen,
              reader_runner: ->(path) { reader_launch_service.run_reader(path) }
            )
          end
          private_class_method :build_workflow_ports

          def build_workflows(context:, workflow_ports:)
            {
              download_workflow: build_download_workflow(context: context, workflow_ports: workflow_ports),
              dictionary_workflow: build_dictionary_workflow(context: context),
              translator_workflow: build_translator_workflow(context: context),
              annotation_workflow: build_annotation_workflow(context: context, workflow_ports: workflow_ports),
            }
          end
          private_class_method :build_workflows

          def state_controller_deps(context:, reader_launch_service:, workflows:)
            Shoko::Adapters::Input::Controllers::Menu::StateController::Dependencies.new(
              reader_launch_service: reader_launch_service,
              workflows: Shoko::Adapters::Input::Controllers::Menu::StateController::WorkflowDependencies.new(**workflows),
              catalog: context.catalog_service
            ).validate!
          end
          private_class_method :state_controller_deps

          def build_reader_launch_service(menu:, context:, reader_controller_builder:)
            ReaderLaunchServiceFactory.build(
              menu: menu,
              context: context,
              reader_controller_builder: reader_controller_builder
            )
          end
          private_class_method :build_reader_launch_service

          def build_download_workflow(context:, workflow_ports:)
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/download_workflow'
              Shoko::Application::Workflows::Menu::DownloadWorkflow.new(
                download_service: context.download_service,
                app_config_store: context.app_config_store,
                menu_session_store: context.menu_session_store,
                menu_transient_store: context.menu_transient_store,
                catalog_refresh_control: workflow_ports,
                text_sanitizer: context.text_sanitizer,
                path_ops: context.path_ops,
                logger: context.logger
              )
            end
          end
          private_class_method :build_download_workflow

          def build_dictionary_workflow(context:)
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/dictionary_workflow'
              Shoko::Application::Workflows::Menu::DictionaryWorkflow.new(
                dictionary_catalog_service: context.dictionary_catalog_service,
                dictionary_storage: context.dictionary_storage,
                app_config_store: context.app_config_store,
                menu_session_store: context.menu_session_store,
                menu_transient_store: context.menu_transient_store,
                file_probe: context.file_probe,
                path_ops: context.path_ops,
                logger: context.logger
              )
            end
          end
          private_class_method :build_dictionary_workflow

          def build_translator_workflow(context:)
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/translator_workflow'
              Shoko::Application::Workflows::Menu::TranslatorWorkflow.new(
                translation_service: context.translation_service,
                menu_session_store: context.menu_session_store,
                menu_transient_store: context.menu_transient_store,
                logger: context.logger
              )
            end
          end
          private_class_method :build_translator_workflow

          def build_annotation_workflow(context:, workflow_ports:)
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/annotation_workflow'
              Shoko::Application::Workflows::Menu::AnnotationWorkflow.new(
                mode_switcher: workflow_ports,
                menu_session_store: context.menu_session_store,
                reader_session_store: context.reader_session_store,
                annotation_service: context.annotation_service,
                logger: context.logger,
                selected_annotation_reader: workflow_ports,
                annotations_view_refresher: workflow_ports,
                reader_runner: workflow_ports,
                menu_transient_store: context.menu_transient_store
              )
            end
          end
          private_class_method :build_annotation_workflow
        end
      end
    end
  end
end
