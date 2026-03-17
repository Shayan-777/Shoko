# frozen_string_literal: true

require_relative '../../../shared/lazy_proxy'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Builds menu state controller and workflow graph for menu composition.
        module MenuStateControllerComposer
          CompositionContext = Struct.new(
            :container,
            :menu_state_reader,
            :menu_session_mutator,
            :reader_state_reader,
            :app_config_store,
            :reader_session_store,
            :reader_runtime_context,
            :pagination_orchestrator,
            :catalog_service,
            :logger,
            :runtime_config,
            :file_probe,
            :path_ops,
            :clock,
            :reader_launch_state,
            :menu_launch_state
          )

          module_function

          def call(menu:, context:, reader_controller_builder:)
            c = context.container

            reader_launch_service = build_reader_launch_service(
              menu: menu,
              context: context,
              reader_controller_builder: reader_controller_builder
            )

            workflow_ports = Shoko::Adapters::Input::Controllers::Menu::WorkflowPortsAdapter.new(
              menu: menu,
              catalog: context.catalog_service,
              reader_runner: ->(path) { reader_launch_service.run_reader(path) }
            )

            download_workflow = build_download_workflow(context: context, workflow_ports: workflow_ports)
            dictionary_workflow = build_dictionary_workflow(context: context)
            annotation_workflow = build_annotation_workflow(context: context, workflow_ports: workflow_ports)

            state_controller_deps = Shoko::Adapters::Input::Controllers::Menu::StateController::Dependencies.new(
              menu_state_reader: context.menu_state_reader,
              menu_session_mutator: context.menu_session_mutator,
              reader_launch_service: reader_launch_service,
              download_workflow: download_workflow,
              dictionary_workflow: dictionary_workflow,
              annotation_workflow: annotation_workflow,
              catalog: context.catalog_service,
              logger: context.logger
            ).validate!

            Shoko::Adapters::Input::Controllers::Menu::StateController.new(menu: menu, deps: state_controller_deps)
          end

          def build_reader_launch_service(menu:, context:, reader_controller_builder:)
            c = context.container
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/null_progress_presenter'
              require_relative '../../../application/workflows/menu/reader_launch_service'
              require_relative '../../../application/workflows/menu/reader_launch/path_resolution'
              require_relative '../../../application/workflows/menu/reader_launch/document_preparation'
              require_relative '../../../application/workflows/menu/reader_launch/runtime_execution'
              require_relative '../../../application/workflows/menu/reader_launch/progress_orchestration'

              reader_launch_ports = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchPortsAdapter.new(
                menu: menu,
                menu_session_store: c.resolve(:menu_session_store),
                reader_controller_builder: reader_controller_builder
              )
              path_resolution = Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution::Dependencies.new(
                  cache_pointer_resolver: c.resolve(:cache_pointer_resolver),
                  reader_document_locator: c.resolve(:reader_document_locator),
                  file_probe: context.file_probe,
                  logger: context.logger
                ).validate!
              )
              document_preparation = Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation::Dependencies.new(
                  document_loader: c.resolve(:document_loader),
                  reader_launch_state: context.reader_launch_state,
                  reader_session_store: context.reader_session_store,
                  background_worker_builder: c.resolve(:background_worker_builder),
                  logger: context.logger
                ).validate!
              )
              runtime_execution = Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution::Dependencies.new(
                  menu_session_store: c.resolve(:menu_session_store),
                  reader_session_store: context.reader_session_store,
                  reader_launch_state: context.reader_launch_state,
                  menu_launch_state: context.menu_launch_state,
                  recent_files_repository: c.resolve(:recent_files_repository),
                  catalog: context.catalog_service,
                  menu_runtime: reader_launch_ports,
                  path_resolution: path_resolution,
                  logger: context.logger
                ).validate!
              )
              progress_orchestration = Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration::Dependencies.new(
                  menu_session_store: c.resolve(:menu_session_store),
                  progress_presenters: reader_launch_ports,
                  null_presenter: Shoko::Application::Workflows::Menu::NullProgressPresenter.new,
                  pagination_orchestrator: context.pagination_orchestrator,
                  page_calculator: c.resolve(:page_calculator),
                  app_config_store: context.app_config_store,
                  reader_session_store: context.reader_session_store,
                  pagination_cache_preloader: c.resolve(:pagination_cache_preloader),
                  runtime_config: context.runtime_config,
                  reader_runtime_context: context.reader_runtime_context,
                  logger: context.logger
                ).validate!
              )

              Shoko::Application::Workflows::Menu::ReaderLaunchService.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunchService::Dependencies.new(
                  book_selection: reader_launch_ports,
                  path_resolution: path_resolution,
                  document_preparation: document_preparation,
                  runtime_execution: runtime_execution,
                  progress_orchestration: progress_orchestration
                ).validate!
              )
            end
          end

          def build_download_workflow(context:, workflow_ports:)
            c = context.container
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/download_workflow'

              Shoko::Application::Workflows::Menu::DownloadWorkflow.new(
                download_service: c.resolve(:download_service),
                app_config_store: context.app_config_store,
                menu_session_store: c.resolve(:menu_session_store),
                catalog_refresh_control: workflow_ports,
                text_sanitizer: c.resolve(:text_sanitizer),
                path_ops: context.path_ops,
                logger: context.logger
              )
            end
          end

          def build_dictionary_workflow(context:)
            c = context.container
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/dictionary_workflow'

              Shoko::Application::Workflows::Menu::DictionaryWorkflow.new(
                dictionary_catalog_service: c.resolve(:dictionary_catalog_service),
                dictionary_storage: c.resolve(:dictionary_storage),
                app_config_store: context.app_config_store,
                menu_session_store: c.resolve(:menu_session_store),
                file_probe: context.file_probe,
                path_ops: context.path_ops,
                logger: context.logger
              )
            end
          end

          def build_annotation_workflow(context:, workflow_ports:)
            c = context.container
            Shoko::Shared::LazyProxy.new do
              require_relative '../../../application/workflows/menu/annotation_workflow'

              Shoko::Application::Workflows::Menu::AnnotationWorkflow.new(
                mode_switcher: workflow_ports,
                menu_session_store: c.resolve(:menu_session_store),
                reader_session_store: context.reader_session_store,
                annotation_service: c.resolve(:annotation_service),
                logger: context.logger,
                selected_annotation_reader: workflow_ports,
                annotations_view_refresher: workflow_ports,
                reader_runner: workflow_ports
              )
            end
          end
        end
      end
    end
  end
end
