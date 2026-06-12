# frozen_string_literal: true

require_relative '../../../../shared/lazy_proxy'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module MenuStateControllerComposer
          # Builds the lazy reader-launch workflow graph for the menu runtime.
          module ReaderLaunchServiceFactory
            LaunchComponents = Data.define(
              :reader_launch_ports,
              :path_resolution,
              :document_preparation,
              :runtime_execution,
              :progress_orchestration
            )

            module_function

            def build(menu:, context:, reader_controller_builder:)
              Shoko::Shared::LazyProxy.new do
                require_reader_launch_dependencies
                build_launch_service(
                  build_components(
                    menu: menu,
                    context: context,
                    reader_controller_builder: reader_controller_builder
                  )
                )
              end
            end

            def build_components(menu:, context:, reader_controller_builder:)
              reader_launch_ports = build_reader_launch_ports(
                menu: menu, context: context, reader_controller_builder: reader_controller_builder
              )
              path_resolution = build_path_resolution(context)
              LaunchComponents.new(
                reader_launch_ports: reader_launch_ports,
                path_resolution: path_resolution,
                document_preparation: build_document_preparation(context),
                **build_runtime_components(
                  context: context,
                  reader_launch_ports: reader_launch_ports,
                  path_resolution: path_resolution
                )
              )
            end
            private_class_method :build_components

            def build_runtime_components(context:, reader_launch_ports:, path_resolution:)
              {
                runtime_execution: build_runtime_execution(
                  context: context,
                  reader_launch_ports: reader_launch_ports,
                  path_resolution: path_resolution
                ),
                progress_orchestration: build_progress_orchestration(
                  context: context,
                  reader_launch_ports: reader_launch_ports
                ),
              }
            end
            private_class_method :build_runtime_components

            def build_launch_service(components)
              Shoko::Application::Workflows::Menu::ReaderLaunchService.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunchService::Dependencies.new(
                  book_selection: components.reader_launch_ports,
                  path_resolution: components.path_resolution,
                  document_preparation: components.document_preparation,
                  runtime_execution: components.runtime_execution,
                  progress_orchestration: components.progress_orchestration
                ).validate!
              )
            end
            private_class_method :build_launch_service

            def require_reader_launch_dependencies
              require_relative '../../../../application/workflows/menu/null_progress_presenter'
              require_relative '../../../../application/workflows/menu/reader_launch_service'
              require_relative '../../../../application/workflows/menu/reader_launch/path_resolution'
              require_relative '../../../../application/workflows/menu/reader_launch/document_preparation'
              require_relative '../../../../application/workflows/menu/reader_launch/runtime_execution'
              require_relative '../../../../application/workflows/menu/reader_launch/progress_orchestration'
            end
            private_class_method :require_reader_launch_dependencies

            def build_reader_launch_ports(menu:, context:, reader_controller_builder:)
              Shoko::Adapters::Input::Controllers::Menu::ReaderLaunchPortsAdapter.new(
                menu_state_reader: context.menu_state_reader,
                browse_screen: menu.main_menu_component.browse_screen,
                mode_switcher: ->(mode) { menu.switch_to_mode(mode) },
                menu_session_store: context.menu_session_store,
                menu_transient_store: context.menu_transient_store,
                reader_controller_builder: reader_controller_builder
              )
            end
            private_class_method :build_reader_launch_ports

            def build_path_resolution(context)
              Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::PathResolution::Dependencies.new(
                  cache_pointer_resolver: context.cache_pointer_resolver,
                  reader_document_locator: context.reader_document_locator,
                  file_probe: context.file_probe,
                  logger: context.logger
                ).validate!
              )
            end
            private_class_method :build_path_resolution

            def build_document_preparation(context)
              Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::DocumentPreparation::Dependencies.new(
                  document_loader: context.document_loader,
                  reader_launch_state: context.reader_launch_state,
                  reader_session_store: context.reader_session_store,
                  background_worker_builder: context.background_worker_builder,
                  logger: context.logger
                ).validate!
              )
            end
            private_class_method :build_document_preparation

            def build_runtime_execution(context:, reader_launch_ports:, path_resolution:)
              Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution.new(
                deps: Shoko::Application::Workflows::Menu::ReaderLaunch::RuntimeExecution::Dependencies.new(
                  menu_session_store: context.menu_session_store,
                  reader_session_store: context.reader_session_store,
                  reader_launch_state: context.reader_launch_state,
                  menu_launch_state: context.menu_launch_state,
                  recent_files_repository: context.recent_files_repository,
                  catalog: context.catalog_service,
                  menu_runtime: reader_launch_ports,
                  path_resolution: path_resolution,
                  logger: context.logger
                ).validate!
              )
            end
            private_class_method :build_runtime_execution

            def build_progress_orchestration(context:, reader_launch_ports:)
              Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration.new(
                deps: progress_orchestration_dependencies(
                  context: context,
                  reader_launch_ports: reader_launch_ports
                )
              )
            end
            private_class_method :build_progress_orchestration

            def progress_orchestration_dependencies(context:, reader_launch_ports:)
              Shoko::Application::Workflows::Menu::ReaderLaunch::ProgressOrchestration::Dependencies.new(
                menu_session_store: context.menu_session_store,
                progress_presenters: reader_launch_ports,
                null_presenter: Shoko::Application::Workflows::Menu::NullProgressPresenter.new,
                pagination_orchestrator: context.pagination_orchestrator,
                page_calculator: context.page_calculator,
                app_config_store: context.app_config_store,
                reader_session_store: context.reader_session_store,
                reader_view_state_store: context.reader_view_state_store,
                reader_pagination_store: context.reader_pagination_store,
                pagination_cache_preloader: context.pagination_cache_preloader,
                runtime_config: context.runtime_config,
                reader_runtime_context: context.reader_runtime_context,
                logger: context.logger
              ).validate!
            end
            private_class_method :progress_orchestration_dependencies
          end
        end
      end
    end
  end
end
