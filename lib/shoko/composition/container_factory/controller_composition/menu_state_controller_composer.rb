# frozen_string_literal: true

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

            menu_runtime = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchRuntimeBridge.new(
              menu: menu,
              reader_controller_builder: reader_controller_builder
            )
            book_selection = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchBookSelectionBridge.new(
              menu: menu,
              logger: context.logger
            )
            progress_presenters = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchProgressPresenters.new(
              presenter_builder: lambda {
                Shoko::Application::Workflows::Menu::MenuProgressPresenter.new(c.resolve(:menu_session_store))
              }
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
                menu_runtime: menu_runtime,
                path_resolution: path_resolution,
                logger: context.logger
              ).validate!
            )
            progress_orchestration = Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration::Dependencies.new(
                menu_session_store: c.resolve(:menu_session_store),
                progress_presenters: progress_presenters,
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

            reader_launch_service = Shoko::Application::Workflows::Menu::ReaderLaunchService.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunchService::Dependencies.new(
                book_selection: book_selection,
                path_resolution: path_resolution,
                document_preparation: document_preparation,
                runtime_execution: runtime_execution,
                progress_orchestration: progress_orchestration
              ).validate!
            )

            catalog_refresh_control = Shoko::Adapters::Input::Controllers::Menu::CatalogRefreshBridge.new(
              catalog: context.catalog_service
            )
            annotation_mode_switcher = Shoko::Adapters::Input::Controllers::Menu::MenuModeSwitcherBridge.new(menu: menu)
            annotation_selection_reader = Shoko::Adapters::Input::Controllers::Menu::AnnotationSelectionBridge.new(
              menu: menu,
              logger: context.logger
            )
            annotation_view_refresher = Shoko::Adapters::Input::Controllers::Menu::AnnotationViewRefreshBridge.new(
              menu: menu,
              logger: context.logger
            )
            reader_runner = Shoko::Adapters::Input::Controllers::Menu::ReaderRunnerBridge.new(
              menu: menu
            )

            download_workflow = Shoko::Application::Workflows::Menu::DownloadWorkflow.new(
              download_service: c.resolve(:download_service),
              menu_session_store: c.resolve(:menu_session_store),
              catalog_refresh_control: catalog_refresh_control,
              text_sanitizer: c.resolve(:text_sanitizer),
              path_ops: context.path_ops,
              logger: context.logger
            )
            dictionary_workflow = Shoko::Application::Workflows::Menu::DictionaryWorkflow.new(
              dictionary_catalog_service: c.resolve(:dictionary_catalog_service),
              dictionary_storage: c.resolve(:dictionary_storage),
              app_config_store: context.app_config_store,
              menu_session_store: c.resolve(:menu_session_store),
              file_probe: context.file_probe,
              path_ops: context.path_ops,
              logger: context.logger
            )
            annotation_workflow = Shoko::Application::Workflows::Menu::AnnotationWorkflow.new(
              mode_switcher: annotation_mode_switcher,
              menu_session_store: c.resolve(:menu_session_store),
              reader_session_store: context.reader_session_store,
              annotation_service: c.resolve(:annotation_service),
              logger: context.logger,
              selected_annotation_reader: annotation_selection_reader,
              annotations_view_refresher: annotation_view_refresher,
              reader_runner: reader_runner
            )

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
        end
      end
    end
  end
end
