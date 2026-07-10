# frozen_string_literal: true

require_relative '../adapters/storage/background_worker'
require_relative '../adapters/storage/background_worker_builder_adapter'
require_relative '../adapters/storage/atomic_file_writer'
require_relative '../adapters/monitoring/performance_monitor'
require_relative '../adapters/monitoring/perf_tracer'
require_relative '../adapters/monitoring/logger_adapter'
require_relative '../shared/lazy_proxy'
require_relative '../core/services/null_logger'
require_relative '../adapters/storage/pagination_cache'
require_relative '../adapters/storage/cache_paths'
require_relative '../adapters/storage/epub_cache'
require_relative '../adapters/output/terminal/cli_progress_renderer'
require_relative '../adapters/output/clipboard/clipboard_service'
require_relative '../adapters/output/notification_service'
require_relative '../adapters/output/terminal/text_metrics'
require_relative '../adapters/output/terminal/text_metrics_port_adapter'
require_relative '../adapters/output/terminal/terminal_service'
require_relative '../adapters/output/terminal/terminal_session_adapter'
require_relative '../adapters/storage/repositories/cached_library_repository'
require_relative '../adapters/storage/repositories/display_metadata_cache_repository'
require_relative '../adapters/ui/render_registry'
require_relative '../adapters/runtime/inline_executor_adapter'
require_relative '../adapters/storage/config_storage_adapter'
require_relative '../adapters/storage/json_cache_store'
require_relative '../adapters/storage/cache_pointer_manager'
require_relative '../adapters/output/instrumentation_service'
require_relative '../adapters/output/terminal_capabilities_adapter'
require_relative '../adapters/storage/cache_pointer_resolver'
require_relative '../adapters/storage/cache_availability_adapter'
require_relative '../adapters/storage/recent_files_repository'
require_relative '../adapters/storage/file_probe_adapter'
require_relative '../adapters/storage/path_ops_adapter'
require_relative '../adapters/input/key_classifier_adapter'
require_relative '../adapters/output/terminal/text_sanitizer_adapter'
require_relative '../adapters/storage/dictionary_availability_adapter'
require_relative '../adapters/book_sources/book_finder'
require_relative '../adapters/book_sources/book_file_probe'
require_relative '../adapters/book_sources/folder_scanner'
require_relative '../adapters/book_sources/library_scanner'
require_relative '../adapters/book_sources/metadata_reader_adapter'
require_relative '../adapters/book_sources/archive/zip_reader'
require_relative '../shared/download_source_policy'
require_relative '../adapters/runtime/env_runtime_config_adapter'
require_relative '../adapters/runtime/rexml_security_limits_adapter'
require_relative '../adapters/runtime/process_control_adapter'
require_relative '../adapters/runtime/monotonic_clock_adapter'
require_relative '../adapters/runtime/system_wall_clock_adapter'
require_relative '../adapters/runtime/uuid_generator_adapter'
require_relative '../adapters/input/input_system_factory_adapter'
require_relative '../adapters/ui/rendering_factory'
require_relative '../adapters/output/terminal/null_terminal_capabilities'
require_relative '../adapters/output/layout/default_layout_metrics'
require_relative '../adapters/runtime/session_state/app_config_store_adapter'
require_relative '../application/state/schema_registry'
require_relative '../application/state/observer_state_store'
require_relative '../core/reading/schema'
require_relative '../application/state/schema/reader_process'
require_relative '../application/state/schema/reader_pagination'
require_relative '../application/state/schema/reader_view'
require_relative '../application/state/schema/menu_process'
require_relative '../application/state/schema/menu_transient'
require_relative '../application/state/schema/config'
require_relative '../application/state/schema/ui_globals'
require_relative '../adapters/output/layout/layout_metrics_adapter'
require_relative '../adapters/runtime/session_state/observer_registry_adapter'
require_relative '../adapters/ui/state/reader_component_registry'
require_relative '../adapters/runtime/session_state/reader_session_mutator'
require_relative '../adapters/runtime/session_state/rendered_content_reader_adapter'
require_relative '../adapters/runtime/session_state/reader_session_store_adapter'
require_relative '../adapters/runtime/session_state/reader_view_state_store_adapter'
require_relative '../adapters/runtime/session_state/reader_pagination_store_adapter'
require_relative '../adapters/runtime/session_state/reader_snapshot_projection_adapter'
require_relative '../adapters/runtime/session_state/menu_session_store_adapter'
require_relative '../adapters/runtime/session_state/menu_transient_store_adapter'
require_relative '../adapters/runtime/session_state/menu_snapshot_projection_adapter'
require_relative '../adapters/runtime/session_state/menu_session_mutator'
require_relative '../adapters/runtime/session_state/reader_runtime_context_adapter'
require_relative '../adapters/runtime/session_state/session_schema_reset_guard'
require_relative '../adapters/runtime/session_state/render_state_writer_adapter'
require_relative '../adapters/runtime/session_state/notification_writer_adapter'
require_relative '../adapters/runtime/session_state/reader_launch_state_adapter'
require_relative '../adapters/runtime/session_state/menu_launch_state_adapter'
require_relative '../adapters/output/formatting/wrapped_lines_provider_adapter'
require_relative '../adapters/ui/rendering/noop_terminal_state_writer'
require_relative '../adapters/ui/view_models/reader_view_model_builder'
require_relative 'dependency_container'
require_relative 'container_factory/infrastructure_registration'
require_relative 'container_factory/port_and_repository_registration'
require_relative 'container_factory/domain_application_registration'
require_relative 'container_factory/controller_composition'
require_relative '../adapters/ui/component_factory'
require_relative '../application/use_cases/catalog_service'

module Shoko
  module Composition
    # Factory methods for creating fully-wired application containers.
    module ContainerFactory
      CliFolderImportContext = Data.define(:workflow, :cli_progress_renderer, :progress_presenter_factory)

      class << self
        include InfrastructureRegistration
        include PortAndRepositoryRegistration
        include DomainApplicationRegistration
        include ControllerComposition

        # Create a fully configured dependency container.
        #
        # @param log_config [Hash] Logger configuration from CLI
        # @return [DependencyContainer]
        def create_default_container(log_config: {})
          container = DependencyContainer.new
          register_infrastructure(container, log_config)
          apply_runtime_configuration(container)
          register_core_ports(container)
          register_repositories(container)
          register_domain_services(container)
          register_application_services(container)
          register_state_management(container)
          register_library_services(container)
          apply_test_configuration(container)
          container
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

        def build_process_control
          Shoko::Adapters::Runtime::ProcessControlAdapter.new
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

        def build_reader_mode_runner(container)
          Shoko::Adapters::Runtime::ReaderModeRunner.new(
            build_reader_controller: ->(path) { build_reader_controller(container, path) },
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
            build_menu_controller: -> { build_menu_controller(container) },
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

        def apply_test_configuration(container)
          Shoko::TestSupport::TestMode.configure_container(container) if defined?(Shoko::TestSupport::TestMode)
        end

        def lazy_container_service(container, service_name)
          Shoko::Shared::LazyProxy.new { container.resolve(service_name) }
        end
      end
    end
  end
end
