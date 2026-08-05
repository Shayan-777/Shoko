# frozen_string_literal: true

require_relative 'container_factory/registration_pipeline'

module Shoko
  module Composition
    # Factory methods for creating fully-wired application containers.
    module ContainerFactory
      CliFolderImportContext = Data.define(:workflow, :cli_progress_renderer, :progress_presenter_factory)

      class << self
        # Create a fully configured dependency container.
        #
        # @param log_config [Hash] Logger configuration from CLI
        # @return [DependencyContainer]
        def create_default_container(log_config: {})
          FormatRegistryComposition.register!
          container = DependencyContainer.new
          registration_pipeline.register_all(container, log_config: log_config)
        end

        def build_menu_controller(container)
          registration_pipeline.build_menu_controller(container)
        end

        def build_reader_controller(container, epub_path, preloaded_document: nil, background_worker: nil)
          registration_pipeline.build_reader_controller(
            container, epub_path,
            preloaded_document: preloaded_document,
            background_worker: background_worker
          )
        end

        def build_unified_application(epub_path:, log_config:)
          require_relative '../adapters/runtime/reader_mode_runner'
          require_relative '../adapters/runtime/app_mode_runner_adapter'

          container = create_default_container(log_config: log_config)
          reader_mode_runner = build_reader_mode_runner(container)
          app_mode_runner = build_app_mode_runner(container, reader_mode_runner)
          container.register(:app_mode_runner, app_mode_runner)
          build_unified_application_instance(epub_path, app_mode_runner)
        end

        # Context for the pre-pagination batch child process spawned by the
        # menu warmup: same composition as the app, but the only consumer is
        # the batch workflow and progress goes to stdout as JSON lines.
        def build_prepagination_batch_context(log_config:)
          require_relative '../application/workflows/menu/library_prepagination_batch'
          require_relative '../adapters/runtime/prepagination_progress_stream_adapter'

          container = create_default_container(log_config: log_config)
          batch = Shoko::Application::Workflows::Menu::LibraryPrepaginationBatch
          batch.new(
            deps: batch::Dependencies.new(
              catalog_service: container.resolve(:catalog_service),
              cache_availability: container.resolve(:cache_availability),
              document_loader: container.resolve(:document_loader),
              page_calculator: container.resolve(:page_calculator),
              app_config_store: container.resolve(:app_config_store),
              progress_writer: Shoko::Adapters::Runtime::PrepaginationProgressStreamAdapter.new,
              logger: container.resolve(:logger)
            )
          )
        end

        def build_cli_folder_import_context(log_config:)
          require_relative '../adapters/book_sources/cache_import_adapter'
          require_relative '../adapters/runtime/cli_progress_presenter'
          require_relative '../application/workflows/cli/folder_import_workflow'
          require_relative '../application/workflows/cli/folder_import_readiness_warmup'

          container = create_default_container(log_config: log_config)
          renderer = container.resolve(:cli_progress_renderer)
          CliFolderImportContext.new(
            workflow: build_folder_import_workflow(container),
            cli_progress_renderer: renderer,
            progress_presenter_factory: build_cli_progress_presenter_factory(renderer)
          )
        end

        private

        # Retained as the factory's formatting-construction seam. A small
        # number of composition consumers build this resolver independently of
        # the default container.
        def build_format_parser_resolver(xhtml_factory, logger)
          registration_pipeline.build_format_parser_resolver(xhtml_factory, logger)
        end

        def build_reader_mode_runner(container)
          Shoko::Adapters::Runtime::ReaderModeRunner.new(
            build_reader_controller: ->(path) { registration_pipeline.build_reader_controller(container, path) },
            logger: container.resolve(:logger),
            **reader_mode_runner_services(container)
          )
        end

        def reader_mode_runner_services(container)
          {
            terminal_session: lazy_container_service(container, :terminal_session),
            instrumentation_service: lazy_container_service(container, :instrumentation_service),
            cache_availability: lazy_container_service(container, :cache_availability),
            document_loader: lazy_container_service(container, :document_loader),
            cli_progress_renderer: lazy_container_service(container, :cli_progress_renderer),
            page_calculator: lazy_container_service(container, :page_calculator),
            app_config_store: lazy_container_service(container, :app_config_store),
            reader_session_store: lazy_container_service(container, :reader_session_store),
            reader_pagination_store: lazy_container_service(container, :reader_pagination_store),
            reader_runtime_context: lazy_container_service(container, :reader_runtime_context),
            reader_launch_state: lazy_container_service(container, :reader_launch_state),
            instrumentation: lazy_container_service(container, :instrumentation),
          }
        end

        def build_app_mode_runner(container, reader_mode_runner)
          Shoko::Adapters::Runtime::AppModeRunnerAdapter.new(
            reader_mode_runner: reader_mode_runner,
            build_menu_controller: -> { registration_pipeline.build_menu_controller(container) },
            library_prepagination_warmup: lazy_container_service(container, :library_prepagination_warmup)
          )
        end

        def build_unified_application_instance(epub_path, app_mode_runner)
          deps = Shoko::Application::UnifiedApplication::Dependencies.new(app_mode_runner: app_mode_runner)

          Shoko::Application::UnifiedApplication.new(epub_path, deps: deps)
        end

        def build_folder_import_workflow(container)
          document_warmup = build_folder_import_document_warmup(container)
          Shoko::Application::Workflows::Cli::FolderImportWorkflow.new(
            scanner: container.resolve(:folder_scanner),
            importer: Shoko::Adapters::BookSources::CacheImportAdapter.new(
              document_loader: container.resolve(:document_loader),
              document_warmup: document_warmup
            ),
            clock: container.resolve(:clock),
            path_ops: container.resolve(:path_ops),
            logger: container.resolve(:logger)
          )
        end

        def build_folder_import_document_warmup(container)
          Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup.new(
            deps: Shoko::Application::Workflows::Cli::FolderImportReadinessWarmup::Dependencies.new(
              page_calculator: container.resolve(:page_calculator),
              app_config_store: container.resolve(:app_config_store),
              reader_view_state_store: container.resolve(:reader_view_state_store),
              reader_runtime_context: container.resolve(:reader_runtime_context),
              logger: container.resolve(:logger)
            )
          )
        end

        def build_cli_progress_presenter_factory(renderer)
          lambda do
            Shoko::Adapters::Runtime::CLIProgressPresenter.new(renderer: renderer)
          end
        end

        def lazy_container_service(container, service_name)
          Shoko::Shared::LazyProxy.new { container.resolve(service_name) }
        end

        def registration_pipeline
          @registration_pipeline ||= RegistrationPipeline.new
        end
      end
    end
  end
end
