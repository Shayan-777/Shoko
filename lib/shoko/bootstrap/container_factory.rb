# frozen_string_literal: true

require_relative '../adapters/storage/background_worker'
require_relative '../adapters/storage/atomic_file_writer'
require_relative '../adapters/monitoring/performance_monitor'
require_relative '../adapters/monitoring/perf_tracer'
require_relative '../adapters/monitoring/logger_adapter'
require_relative '../core/services/null_logger'
require_relative '../adapters/storage/pagination_cache'
require_relative '../adapters/storage/cache_paths'
require_relative '../adapters/storage/epub_cache'
require_relative '../adapters/output/kitty/kitty_image_renderer'
require_relative '../adapters/output/terminal/cli_progress_renderer'
require_relative '../adapters/output/kitty/display_capabilities'
require_relative '../adapters/output/terminal/text_metrics'
require_relative '../adapters/output/terminal/text_metrics_port_adapter'
require_relative '../adapters/storage/repositories/cached_library_repository'
require_relative '../adapters/ui/render_registry'
require_relative '../core/events/domain_event_bus'
require_relative '../core/services/default_display_capabilities'
require_relative '../core/services/inline_executor'
require_relative '../adapters/storage/file_writer_service'
require_relative '../adapters/storage/dictionary_catalog_service'
require_relative '../adapters/storage/sqlite_dictionary_adapter'
require_relative '../adapters/storage/config_storage_adapter'
require_relative '../adapters/output/instrumentation_service'
require_relative '../adapters/output/terminal_capabilities_adapter'
require_relative '../adapters/book_sources/download_service'
require_relative '../adapters/storage/cache_pointer_resolver'
require_relative '../adapters/storage/cache_availability_adapter'
require_relative '../adapters/storage/recent_files_repository'
require_relative '../adapters/storage/file_probe_adapter'
require_relative '../adapters/storage/path_ops_adapter'
require_relative '../adapters/input/command_factory'
require_relative '../adapters/input/key_classifier_adapter'
require_relative '../adapters/output/terminal/text_sanitizer_adapter'
require_relative '../adapters/storage/dictionary_availability_adapter'
require_relative '../adapters/storage/dictionary_storage_adapter'
require_relative '../adapters/storage/data_cleanup_adapter'
require_relative '../adapters/storage/cache_manager_adapter'
require_relative '../adapters/book_sources/book_finder'
require_relative '../adapters/book_sources/folder_scanner'
require_relative '../adapters/book_sources/cache_import_adapter'
require_relative '../adapters/book_sources/gutendex_client'
require_relative '../adapters/book_sources/metadata_reader_adapter'
require_relative '../adapters/book_sources/epub/epub_resource_loader'
require_relative '../adapters/runtime/env_runtime_config_adapter'
require_relative '../adapters/runtime/rexml_security_limits_adapter'
require_relative '../adapters/runtime/process_control_adapter'
require_relative '../adapters/runtime/monotonic_clock_adapter'
require_relative '../adapters/input/input_system_factory_adapter'
require_relative '../adapters/ui/rendering_factory'
require_relative '../core/services/dictionary_service'
require_relative '../core/services/default_terminal_capabilities'
require_relative '../core/services/default_layout_metrics'
require_relative '../core/services/document_path_resolver'
require_relative '../adapters/runtime/session_state/config_reader_adapter'
require_relative '../adapters/output/layout/layout_metrics_adapter'
require_relative '../adapters/runtime/session_state/state_writer_adapter'
require_relative '../adapters/runtime/session_state/rendered_content_reader_adapter'
require_relative '../adapters/runtime/session_state/reader_state_reader_adapter'
require_relative '../adapters/runtime/session_state/ui_state_reader_adapter'
require_relative '../adapters/runtime/session_state/render_state_writer_adapter'
require_relative '../adapters/runtime/session_state/sidebar_state_reader_adapter'
require_relative '../adapters/runtime/session_state/menu_state_reader_adapter'
require_relative '../adapters/runtime/session_state/menu_state_writer_adapter'
require_relative '../adapters/runtime/session_state/notification_writer_adapter'
require_relative '../application/use_cases/command_bus'
require_relative '../adapters/runtime/session_state/event_publisher_adapter'
require_relative '../adapters/output/formatting/wrapped_lines_provider_adapter'
require_relative '../adapters/ui/view_models/reader_view_model_builder'
require_relative 'dependency_container'
require_relative 'reader_session_context'
require_relative 'menu_session_context'
require_relative 'container_factory/infrastructure_registration'
require_relative 'container_factory/port_and_repository_registration'
require_relative 'container_factory/domain_application_registration'
require_relative 'container_factory/controller_composition'
require_relative 'container_factory/test_container_registration'
require_relative '../adapters/ui/component_factory'
require_relative '../adapters/ui/sessions/dictionary_ui_session_adapter'
require_relative '../adapters/ui/sessions/in_book_search_ui_session_adapter'
require_relative '../adapters/ui/sessions/annotation_overlay_ui_session_adapter'
require_relative '../application/services/popup_position_service'
require_relative '../application/cli_progress_presenter'
require_relative '../application/workflows/cli/folder_import_workflow'

module Shoko
  module Bootstrap
    # Factory methods for creating fully-wired application containers.
    module ContainerFactory
      CliFolderImportContext = Data.define(:workflow, :cli_progress_renderer, :progress_presenter_factory)

      class << self
        include InfrastructureRegistration
        include PortAndRepositoryRegistration
        include DomainApplicationRegistration
        include ControllerComposition
        include TestContainerRegistration

        # Create a fully configured dependency container.
        #
        # @param log_config [Hash] Logger configuration from CLI
        # @return [DependencyContainer]
        def create_default_container(log_config: {})
          container = DependencyContainer.new
          event_bus = register_infrastructure(container, log_config)
          apply_runtime_configuration(container)
          register_core_ports(container)
          register_repositories(container)
          register_domain_services(container)
          register_application_services(container)
          register_state_management(container, event_bus)
          register_library_services(container)
          apply_test_configuration(container)
          container
        end

        def build_unified_application(epub_path:, log_config:)
          container = create_default_container(log_config: log_config)
          deps = Shoko::Application::UnifiedApplication::Dependencies.new(
            build_reader_controller: ->(path) { build_reader_controller(container, path) },
            build_menu_controller: -> { build_menu_controller(container) },
            terminal_service: container.resolve(:terminal_service),
            instrumentation_service: container.resolve_optional(:instrumentation_service),
            cache_availability: container.resolve_optional(:cache_availability),
            document_service_factory: container.resolve_optional(:document_service_factory),
            cli_progress_renderer: container.resolve(:cli_progress_renderer),
            page_calculator: container.resolve_optional(:page_calculator),
            config_reader: container.resolve_optional(:config_reader),
            state_writer: container.resolve_optional(:state_writer),
            reader_state_reader: container.resolve_optional(:reader_state_reader),
            reader_session_context: container.resolve_optional(:reader_session_context),
            instrumentation: container.resolve_optional(:instrumentation),
            logger: container.resolve_optional(:logger)
          )

          Shoko::Application::UnifiedApplication.new(epub_path, deps: deps)
        end

        def build_cli_folder_import_context(log_config:)
          container = create_default_container(log_config: log_config)
          renderer = container.resolve(:cli_progress_renderer)
          workflow = Shoko::Application::Workflows::Cli::FolderImportWorkflow.new(
            scanner: Shoko::Adapters::BookSources::FolderScanner.new,
            importer: Shoko::Adapters::BookSources::CacheImportAdapter.new(
              document_service_factory: container.resolve(:document_service_factory)
            ),
            clock: container.resolve(:clock),
            logger: container.resolve_optional(:logger)
          )

          presenter_factory = lambda do
            Shoko::Application::CLIProgressPresenter.new(renderer: renderer)
          end

          CliFolderImportContext.new(
            workflow: workflow,
            cli_progress_renderer: renderer,
            progress_presenter_factory: presenter_factory
          )
        end
      end
    end
  end
end
