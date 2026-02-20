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
require_relative '../presentation/ui/render_registry'
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
require_relative '../adapters/book_sources/gutendex_client'
require_relative '../adapters/book_sources/metadata_reader_adapter'
require_relative '../adapters/book_sources/epub/epub_resource_loader'
require_relative '../adapters/runtime/env_runtime_config_adapter'
require_relative '../adapters/runtime/rexml_security_limits_adapter'
require_relative '../adapters/runtime/process_control_adapter'
require_relative '../adapters/runtime/monotonic_clock_adapter'
require_relative '../adapters/input/input_system_factory_adapter'
require_relative '../presentation/ui/rendering_factory'
require_relative '../core/services/dictionary_service'
require_relative '../core/services/default_terminal_capabilities'
require_relative '../core/services/default_layout_metrics'
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
require_relative '../adapters/input/command_port_adapter'
require_relative '../adapters/runtime/session_state/event_publisher_adapter'
require_relative '../adapters/output/formatting/wrapped_lines_provider_adapter'
require_relative '../application/ui/reader_view_model_builder'
require_relative 'dependency_container'
require_relative 'reader_session_context'
require_relative 'menu_session_context'
require_relative 'container_factory/infrastructure_registration'
require_relative 'container_factory/port_and_repository_registration'
require_relative 'container_factory/domain_application_registration'
require_relative 'container_factory/controller_composition'
require_relative 'container_factory/test_container_registration'
require_relative '../presentation/ui/component_factory'
require_relative '../presentation/ui/sessions/dictionary_ui_session_adapter'
require_relative '../presentation/ui/sessions/in_book_search_ui_session_adapter'
require_relative '../presentation/ui/sessions/annotation_overlay_ui_session_adapter'
require_relative '../application/services/popup_position_service'

module Shoko
  module Bootstrap
      # Factory methods for creating fully-wired application containers.
      module ContainerFactory
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
        end
      end
  end
end
