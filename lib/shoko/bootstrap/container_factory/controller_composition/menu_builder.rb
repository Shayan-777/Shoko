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

module Shoko
  module Bootstrap
    module ContainerFactory
      module ControllerComposition
        module MenuBuilder
          # Build a fully-wired MenuController.
          def build_menu_controller(container)
            c = container
            rendering_factory = c.resolve(:rendering_factory)
            reader_session_context = c.resolve(:reader_session_context)
            menu_session_context = c.resolve(:menu_session_context)
            terminal_service = c.resolve(:terminal_service)
            ui_state_reader = c.resolve(:ui_state_reader)
            reader_state_reader = c.resolve(:reader_state_reader)
            menu_state_reader = c.resolve(:menu_state_reader)
            menu_state_writer = c.resolve(:menu_state_writer)
            state_writer = c.resolve(:state_writer)
            logger = c.resolve_optional(:logger)
            catalog_service = c.resolve(:catalog_service)
            dictionary_availability = c.resolve_optional(:dictionary_availability)
            dictionary_storage = c.resolve_optional(:dictionary_storage)
            runtime_config = c.resolve_optional(:runtime_config)
            file_probe = c.resolve_optional(:file_probe)
            path_ops = c.resolve_optional(:path_ops)
            clock = c.resolve(:clock)
            process_control = c.resolve_optional(:process_control)
            document = reader_session_context&.document || c.resolve_optional(:document)

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
              pagination_cache: c.resolve_optional(:pagination_cache),
              display_capabilities: c.resolve_optional(:display_capabilities),
              instrumentation: c.resolve_optional(:instrumentation),
              logger: logger
            )

            menu_ui_dependencies = Shoko::Adapters::Ui::MenuUiDependencies.new(
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              reader_state_reader: reader_state_reader,
              sidebar_state_reader: c.resolve_optional(:sidebar_state_reader),
              config_reader: c.resolve_optional(:config_reader),
              runtime_config: runtime_config,
              dictionary_availability: dictionary_availability,
              dictionary_storage: dictionary_storage,
              annotation_service: c.resolve_optional(:annotation_service),
              catalog_service: catalog_service,
              reader_session_context: reader_session_context,
              document: document
            )

            state_controller_factory = lambda do |menu|
              compose_menu_state_controller(
                container: c,
                menu: menu,
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
                reader_session_context: reader_session_context,
                menu_session_context: menu_session_context
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
              notification_service: c.resolve_optional(:notification_service),
              settings_service: c.resolve_optional(:settings_service),
              annotation_service: c.resolve_optional(:annotation_service),
              logger: logger,
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              process_control: process_control
            )

            Shoko::Adapters::Input::Controllers::Menu::Controller.new(deps: menu_deps)
          end

          private

          def compose_menu_state_controller(container:, menu:, menu_state_reader:, menu_state_writer:, reader_state_reader:,
                                            state_writer:, pagination_orchestrator:, catalog_service:, logger:, runtime_config:,
                                            file_probe:, path_ops:, clock:, reader_session_context:,
                                            menu_session_context:)
            c = container
            build_reader_controller_lambda = lambda do |reader_path, preloaded_document:, background_worker:|
              build_reader_controller(
                c,
                reader_path,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              )
            end

            menu_runtime = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchRuntimeBridge.new(
              menu: menu,
              reader_controller_builder: build_reader_controller_lambda
            )
            book_selection = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchBookSelectionBridge.new(
              menu: menu,
              logger: logger
            )
            progress_presenters = Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchProgressPresenters.new(
              presenter_builder: lambda {
                Shoko::Application::Workflows::Menu::MenuProgressPresenter.new(menu_state_writer)
              }
            )

            path_resolution = Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution::Dependencies.new(
                cache_pointer_resolver: c.resolve_optional(:cache_pointer_resolver),
                document_path_resolver: c.resolve_optional(:document_path_resolver),
                file_probe: file_probe,
                logger: logger
              ).validate!
            )
            document_preparation = Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation::Dependencies.new(
                document_service_factory: c.resolve_optional(:document_service_factory),
                reader_session_context: reader_session_context,
                state_writer: state_writer,
                background_worker_factory: c.resolve_optional(:background_worker_factory),
                logger: logger
              ).validate!
            )
            runtime_execution = Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution::Dependencies.new(
                menu_state_reader: menu_state_reader,
                state_writer: state_writer,
                reader_session_context: reader_session_context,
                menu_session_context: menu_session_context,
                recent_files_repository: c.resolve_optional(:recent_files_repository),
                catalog: catalog_service,
                menu_runtime: menu_runtime,
                path_resolution: path_resolution,
                logger: logger
              ).validate!
            )
            progress_orchestration = Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration::Dependencies.new(
                menu_state_reader: menu_state_reader,
                menu_runtime: menu_runtime,
                progress_presenters: progress_presenters,
                null_presenter: Shoko::Application::Workflows::Menu::NullProgressPresenter.new,
                pagination_orchestrator: pagination_orchestrator,
                page_calculator: c.resolve_optional(:page_calculator),
                config_reader: c.resolve_optional(:config_reader),
                reader_state_reader: reader_state_reader,
                sidebar_state_reader: c.resolve_optional(:sidebar_state_reader),
                state_writer: state_writer,
                pagination_cache_preloader: c.resolve_optional(:pagination_cache_preloader),
                runtime_config: runtime_config,
                ui_state_reader: c.resolve(:ui_state_reader),
                clock: clock,
                logger: logger
              ).validate!
            )

            reader_launch_service = Shoko::Application::Workflows::Menu::ReaderLaunchService.new(
              deps: Shoko::Application::Workflows::Menu::ReaderLaunchService::Dependencies.new(
                menu_state_reader: menu_state_reader,
                book_selection: book_selection,
                path_resolution: path_resolution,
                document_preparation: document_preparation,
                runtime_execution: runtime_execution,
                progress_orchestration: progress_orchestration
              ).validate!
            )

            menu_workflow_runtime = Shoko::Adapters::Input::Controllers::Menu::MenuWorkflowRuntimeBridge.new(
              menu: menu,
              catalog: catalog_service
            )
            annotation_mode_switcher = Shoko::Adapters::Input::Controllers::Menu::MenuModeSwitcherBridge.new(menu: menu)
            annotation_selection_reader = Shoko::Adapters::Input::Controllers::Menu::AnnotationSelectionBridge.new(
              menu: menu,
              logger: logger
            )
            annotation_view_refresher = Shoko::Adapters::Input::Controllers::Menu::AnnotationViewRefreshBridge.new(
              menu: menu,
              logger: logger
            )
            reader_runner = Shoko::Adapters::Input::Controllers::Menu::ReaderRunnerBridge.new(
              menu: menu
            )

            download_workflow = Shoko::Application::Workflows::Menu::DownloadWorkflow.new(
              download_service: c.resolve_optional(:download_service),
              menu_state_writer: menu_state_writer,
              menu_runtime: menu_workflow_runtime,
              text_sanitizer: c.resolve_optional(:text_sanitizer),
              path_ops: path_ops,
              clock: clock,
              logger: logger
            )
            dictionary_workflow = Shoko::Application::Workflows::Menu::DictionaryWorkflow.new(
              dictionary_catalog_service: c.resolve_optional(:dictionary_catalog_service),
              dictionary_storage: c.resolve_optional(:dictionary_storage),
              config_reader: c.resolve_optional(:config_reader),
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              menu_runtime: menu_workflow_runtime,
              file_probe: file_probe,
              path_ops: path_ops,
              clock: clock,
              logger: logger
            )
            annotation_workflow = Shoko::Application::Workflows::Menu::AnnotationWorkflow.new(
              mode_switcher: annotation_mode_switcher,
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              state_writer: state_writer,
              annotation_service: c.resolve_optional(:annotation_service),
              logger: logger,
              selected_annotation_reader: annotation_selection_reader,
              annotations_view_refresher: annotation_view_refresher,
              reader_runner: reader_runner
            )

            state_controller_deps = Shoko::Adapters::Input::Controllers::Menu::StateController::Dependencies.new(
              menu_state_reader: menu_state_reader,
              menu_state_writer: menu_state_writer,
              reader_launch_service: reader_launch_service,
              download_workflow: download_workflow,
              dictionary_workflow: dictionary_workflow,
              annotation_workflow: annotation_workflow,
              catalog: catalog_service,
              logger: logger
            ).validate!

            Shoko::Adapters::Input::Controllers::Menu::StateController.new(menu: menu, deps: state_controller_deps)
          end
        end
      end
    end
  end
end
