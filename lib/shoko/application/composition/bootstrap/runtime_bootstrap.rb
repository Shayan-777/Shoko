# frozen_string_literal: true

require_relative 'format_registry_bootstrap'

module Shoko
  module Application
    module Composition
      module Bootstrap
        module RuntimeBootstrap
          FEATURES = %w[
            shoko/adapters/monitoring/logger
            shoko/core/validator
            shoko/adapters/monitoring/performance_monitor
            shoko/adapters/state/event_bus
            shoko/adapters/state/state_store
            shoko/adapters/state/observer_state_store
            shoko/adapters/storage/cache_pointer_manager
            shoko/adapters/storage/cache_availability_adapter
            shoko/adapters/storage/book_cache_pipeline
            shoko/adapters/book_sources/document_service
            shoko/adapters/storage/pagination_cache
            shoko/adapters/book_sources/library_scanner
            shoko/application/services/pagination/pagination_cache_preloader
            shoko/core/book_formats/format_registry
            shoko/shared/errors
            shoko/shared/optional_dependency
            shoko/core/models/reader_settings
            shoko/adapters/output/ui/constants/ui_constants
            shoko/adapters/output/ui/constants/themes
            shoko/adapters/output/ui/constants/messages
            shoko/adapters/output/ui/constants/highlighting
            shoko/adapters/output/rendering/models/page_rendering_context
            shoko/adapters/output/rendering/models/rendering_context
            shoko/adapters/output/rendering/models/line_geometry
            shoko/core/models/selection_anchor
            shoko/adapters/output/ui/builders/page_setup_builder
            shoko/shared/version
            shoko/adapters/output/terminal/terminal
            shoko/adapters/input/validators/file_path_validator
            shoko/adapters/input/validators/terminal_size_validator
            shoko/adapters/book_sources/book_finder
            shoko/adapters/storage/recent_files
            shoko/adapters/book_sources/book_document
            shoko/adapters/output/terminal/text_metrics
            shoko/adapters/output/kitty/display_capabilities
            shoko/adapters/input/command_factory
            shoko/adapters/input/annotations/mouse_handler
            shoko/application/dependency_container
            shoko/core/models/book_data
            shoko/core/models/chapter
            shoko/core/models/bookmark
            shoko/core/models/bookmark_data
            shoko/core/models/toc_entry
            shoko/core/models/content_block
            shoko/core/ports/bookmark_repository
            shoko/core/ports/annotation_repository
            shoko/core/ports/cache_manager
            shoko/core/ports/cache_pointer_resolver
            shoko/core/ports/cache_availability
            shoko/core/ports/dictionary_availability
            shoko/application/ports/input_system_factory
            shoko/core/ports/key_classifier
            shoko/core/ports/metadata_reader
            shoko/core/ports/recent_files_repository
            shoko/core/ports/event_publisher
            shoko/core/ports/text_sanitizer
            shoko/core/ports/text_metrics
            shoko/core/ports/display_capabilities
            shoko/core/ports/instrumentation
            shoko/core/ports/async_executor
            shoko/core/ports/observer_registry
            shoko/core/ports/wrapped_lines_provider
            shoko/application/ports/rendering_factory
            shoko/application/ports/ui_component_factory
            shoko/application/ports/render_state_writer
            shoko/application/ports/dictionary_ui_session
            shoko/application/ports/in_book_search_ui_session
            shoko/application/ports/annotation_overlay_ui_session
            shoko/core/events/base_domain_event
            shoko/core/events/bookmark_events
            shoko/core/events/annotation_events
            shoko/core/events/progress_events
            shoko/core/events/domain_event_bus
            shoko/adapters/storage/repositories/base_repository
            shoko/adapters/storage/repositories/bookmark_repository
            shoko/adapters/storage/repositories/annotation_repository
            shoko/adapters/storage/repositories/progress_repository
            shoko/core/services/base_service
            shoko/core/services/default_text_metrics
            shoko/core/services/default_display_capabilities
            shoko/core/services/null_instrumentation
            shoko/core/services/inline_executor
            shoko/application/services/reader/navigation_service
            shoko/application/services/reader/navigation/context_helpers
            shoko/application/services/reader/bookmark_service
            shoko/core/services/page_calculator_service
            shoko/core/services/coordinate_service
            shoko/core/services/layout_service
            shoko/adapters/output/clipboard/clipboard_service
            shoko/core/services/annotation_service
            shoko/core/services/in_book_search_service
            shoko/adapters/output/terminal/terminal_service
            shoko/core/services/selection_service
            shoko/adapters/output/formatting/wrapping_service
            shoko/adapters/output/formatting/formatting_service
            shoko/adapters/output/ui/component_factory
            shoko/adapters/output/notification_service
            shoko/adapters/storage/cache_pointer_resolver
            shoko/adapters/storage/recent_files_repository
            shoko/application/use_cases/catalog_service
            shoko/application/use_cases/settings_service
            shoko/adapters/book_sources/download_service
            shoko/application/use_cases/commands/base_command
            shoko/application/use_cases/commands/navigation_commands
            shoko/application/use_cases/commands/application_commands
            shoko/application/use_cases/commands/bookmark_commands
            shoko/application/use_cases/commands/sidebar_commands
            shoko/application/use_cases/commands/conditional_navigation_commands
            shoko/application/use_cases/commands/menu_commands
            shoko/application/use_cases/commands/annotation_editor_commands
            shoko/application/use_cases/commands/reader_commands
            shoko/adapters/state/actions/base_action
            shoko/adapters/state/actions/update_state_action
            shoko/adapters/state/actions/toggle_view_mode_action
            shoko/adapters/state/actions/switch_reader_mode_action
            shoko/adapters/state/actions/quit_to_menu_action
            shoko/adapters/state/actions/update_message_action
            shoko/adapters/state/actions/update_config_action
            shoko/adapters/state/actions/update_sidebar_action
            shoko/adapters/state/actions/update_rendered_lines_action
            shoko/adapters/state/actions/update_ui_loading_action
            shoko/adapters/state/actions/update_pagination_state_action
            shoko/adapters/state/actions/update_reader_meta_action
            shoko/adapters/state/actions/update_menu_action
            shoko/adapters/state/event_publisher_adapter
            shoko/adapters/state/observer_registry_adapter
            shoko/adapters/state/selectors/reader_selectors
            shoko/adapters/state/selectors/menu_selectors
            shoko/adapters/state/selectors/config_selectors
            shoko/application/ui/session_outcome
            shoko/application/ui/view_models/reader_view_model
            shoko/application/unified_application
            shoko/application/ui/reader_view_model_builder
            shoko/application/reader_startup_orchestrator
            shoko/adapters/output/ui/rendering/frame_coordinator
            shoko/adapters/output/ui/rendering/render_pipeline
            shoko/application/services/pagination/page_info_calculator
            shoko/application/services/pagination/pagination_orchestrator
            shoko/application/services/pagination/pagination_coordinator
            shoko/adapters/output/ui/rendering/reader_render_coordinator
            shoko/application/reader_lifecycle
            shoko/core/services/progress_helper
            shoko/application/controllers/ui_controller
            shoko/application/controllers/state_controller
            shoko/adapters/input/input_controller
            shoko/adapters/output/ui/components/reading/base_view_renderer
            shoko/adapters/output/ui/components/reading/split_view_renderer
            shoko/adapters/output/ui/components/reading/single_view_renderer
            shoko/adapters/output/ui/components/reading/help_renderer
            shoko/adapters/output/ui/components/reading/view_renderer_factory
            shoko/adapters/output/ui/components/screens/base_screen_component
            shoko/adapters/output/ui/components/screens/menu_screen_component
            shoko/adapters/output/ui/components/screens/annotation_detail_screen_component
            shoko/adapters/output/ui/components/screens/annotation_editor_screen_component
            shoko/adapters/output/ui/components/annotation_editor_overlay_component
            shoko/application/controllers/menu_controller
            shoko/application/controllers/mouseable_reader
            shoko/application/cli
          ].freeze

          module_function

          def boot!
            return if @booted

            # Keep this near bootstrap so `require 'zip'` resolves to our in-repo shim.
            require_relative '../../../../zip'
            FEATURES.each { |feature| require feature }
            FormatRegistryBootstrap.register!
            activate_test_mode_if_needed
            @booted = true
          end

          def activate_test_mode_if_needed
            return unless ENV['SHOKO_TEST_MODE'] == '1'

            require 'shoko/test_support/test_mode'
            Shoko::TestSupport::TestMode.activate!
          end
          private_class_method :activate_test_mode_if_needed
        end
      end
    end
  end
end
