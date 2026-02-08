# frozen_string_literal: true

# Shoko - A fast, keyboard-driven terminal ebook reader
#
# This is the main entry point for the Shoko gem. It loads all
# necessary components in the correct order to ensure dependencies are
# satisfied.
#
# @example Basic usage
#   require 'shoko'
#   Shoko::CLI.run
#
# @example Programmatic usage
#   reader = Shoko::Application::Controllers::MouseableReader.new('/path/to/book.epub')
#   reader.run

module Shoko
  module Adapters
    module Output
      module Ui; end
      module Rendering; end
    end

    module Input; end

    module Storage
      module Repositories; end
    end

    module Monitoring; end

    module BookSources
      module Epub; end
      module Fb2; end
      module Pdf; end
      module Kindle; end
      module Rtf; end
    end

    module State
      module Actions; end
      module Selectors; end
    end
  end

  module Core
    module Services
      module Pagination; end
    end

    module Models; end
    module Events; end

    module BookFormats
      module Epub
        module OPF; end
      end
      module Fb2; end
      module Pdf; end
      module Kindle; end
      module Rtf; end
    end
  end

  module Application
    module Controllers; end
    module UseCases; end
    module State; end
    module UI; end
  end
end

# Core infrastructure - must be loaded first.
# Keep this near bootstrap so `require 'zip'` resolves to our in-repo shim.
require_relative 'zip'
require_relative 'shoko/adapters/monitoring/logger'
require_relative 'shoko/core/validator'
require_relative 'shoko/adapters/monitoring/performance_monitor'
require_relative 'shoko/adapters/state/event_bus'
require_relative 'shoko/adapters/state/state_store'
require_relative 'shoko/adapters/state/observer_state_store'
require_relative 'shoko/adapters/storage/cache_pointer_manager'
require_relative 'shoko/adapters/storage/cache_availability_adapter'
require_relative 'shoko/adapters/storage/book_cache_pipeline'
require_relative 'shoko/adapters/book_sources/document_service'
require_relative 'shoko/adapters/storage/pagination_cache'
require_relative 'shoko/adapters/book_sources/library_scanner'
require_relative 'shoko/adapters/book_sources/gutendex_client'
require_relative 'shoko/core/services/pagination/pagination_cache_preloader'

# Format registry (must load before importers that self-register)
require_relative 'shoko/core/book_formats/format_registry'

# Error definitions
require_relative 'shoko/shared/errors'
require_relative 'shoko/shared/optional_dependency'

# Constants and configuration
require_relative 'shoko/core/models/reader_settings'
require_relative 'shoko/adapters/output/ui/constants/ui_constants'
require_relative 'shoko/adapters/output/ui/constants/themes'
require_relative 'shoko/adapters/output/ui/constants/messages'
require_relative 'shoko/adapters/output/ui/constants/highlighting'
require_relative 'shoko/adapters/output/rendering/models/page_rendering_context'
require_relative 'shoko/adapters/output/rendering/models/rendering_context'
require_relative 'shoko/adapters/output/rendering/models/line_geometry'
require_relative 'shoko/core/models/selection_anchor'
require_relative 'shoko/adapters/output/ui/builders/page_setup_builder'

# Core components
require_relative 'shoko/shared/version'
require_relative 'shoko/adapters/output/terminal/terminal'
# Config/state access uses ObserverStateStore via DI (:global_state resolves to the shared state store)

# Validators
require_relative 'shoko/adapters/input/validators/file_path_validator'
require_relative 'shoko/adapters/input/validators/terminal_size_validator'

# Data management
require_relative 'shoko/adapters/book_sources/book_finder'
require_relative 'shoko/adapters/storage/recent_files'

# Document handling
require_relative 'shoko/adapters/book_sources/epub/epub_importer'
require_relative 'shoko/adapters/book_sources/book_document'
require_relative 'shoko/adapters/book_sources/fb2/fb2_importer'
require_relative 'shoko/core/book_formats/fb2/fb2_content_parser'
require_relative 'shoko/adapters/book_sources/pdf/pdf_importer'
require_relative 'shoko/core/book_formats/pdf/pdf_content_parser'
require_relative 'shoko/adapters/book_sources/kindle/kindle_importer'
require_relative 'shoko/core/book_formats/kindle/kindle_content_parser'
require_relative 'shoko/adapters/book_sources/rtf/rtf_importer'
require_relative 'shoko/core/book_formats/rtf/rtf_content_parser'
require_relative 'shoko/adapters/output/terminal/text_metrics'
require_relative 'shoko/adapters/output/kitty/display_capabilities'

# Input system

require_relative 'shoko/adapters/input/key_definitions'
require_relative 'shoko/adapters/input/command_factory'
require_relative 'shoko/adapters/input/annotations/mouse_handler'

# Domain layer (must load before bridge)
require_relative 'shoko/application/dependency_container'
require_relative 'shoko/core/models/book_data'
require_relative 'shoko/core/models/chapter'
require_relative 'shoko/core/models/bookmark'
require_relative 'shoko/core/models/bookmark_data'
require_relative 'shoko/core/models/toc_entry'
require_relative 'shoko/core/models/content_block'

# Core ports (interfaces for hexagonal architecture)
require_relative 'shoko/core/ports/bookmark_repository'
require_relative 'shoko/core/ports/annotation_repository'
require_relative 'shoko/core/ports/cache_manager'
require_relative 'shoko/core/ports/cache_pointer_resolver'
require_relative 'shoko/core/ports/cache_availability'
require_relative 'shoko/core/ports/dictionary_availability'
require_relative 'shoko/core/ports/input_system_factory'
require_relative 'shoko/core/ports/key_classifier'
require_relative 'shoko/core/ports/metadata_reader'
require_relative 'shoko/core/ports/recent_files_repository'
require_relative 'shoko/core/ports/rendering_factory'
require_relative 'shoko/core/ports/text_sanitizer'
require_relative 'shoko/core/ports/text_metrics'
require_relative 'shoko/core/ports/display_capabilities'
require_relative 'shoko/core/ports/instrumentation'
require_relative 'shoko/core/ports/async_executor'
require_relative 'shoko/core/ports/ui_component_factory'
require_relative 'shoko/core/ports/wrapped_lines_provider'

require_relative 'shoko/core/events/base_domain_event'
require_relative 'shoko/core/events/bookmark_events'
require_relative 'shoko/core/events/annotation_events'
require_relative 'shoko/core/events/progress_events'
require_relative 'shoko/core/events/domain_event_bus'
require_relative 'shoko/adapters/storage/repositories/base_repository'
require_relative 'shoko/adapters/storage/repositories/bookmark_repository'
require_relative 'shoko/adapters/storage/repositories/annotation_repository'
require_relative 'shoko/adapters/storage/repositories/progress_repository'
require_relative 'shoko/adapters/storage/repositories/config_repository'
require_relative 'shoko/core/services/base_service'
require_relative 'shoko/core/services/default_text_metrics'
require_relative 'shoko/core/services/default_display_capabilities'
require_relative 'shoko/core/services/null_instrumentation'
require_relative 'shoko/core/services/inline_executor'
require_relative 'shoko/core/services/navigation_service'
require_relative 'shoko/core/services/navigation/context_helpers'
require_relative 'shoko/core/services/bookmark_service'
require_relative 'shoko/core/services/page_calculator_service'
require_relative 'shoko/core/services/coordinate_service'
require_relative 'shoko/core/services/layout_service'
require_relative 'shoko/adapters/output/clipboard/clipboard_service'
require_relative 'shoko/core/services/annotation_service'
require_relative 'shoko/adapters/output/terminal/terminal_service'
require_relative 'shoko/core/services/selection_service'
require_relative 'shoko/adapters/output/formatting/wrapping_service'
require_relative 'shoko/adapters/output/formatting/formatting_service'
require_relative 'shoko/adapters/output/ui/component_factory'
require_relative 'shoko/adapters/output/notification_service'
require_relative 'shoko/adapters/storage/cache_pointer_resolver'
require_relative 'shoko/adapters/storage/recent_files_repository'
require_relative 'shoko/application/use_cases/catalog_service'
require_relative 'shoko/application/use_cases/settings_service'
require_relative 'shoko/adapters/book_sources/download_service'
require_relative 'shoko/application/use_cases/commands/base_command'
require_relative 'shoko/application/use_cases/commands/navigation_commands'
require_relative 'shoko/application/use_cases/commands/application_commands'
require_relative 'shoko/application/use_cases/commands/bookmark_commands'
require_relative 'shoko/application/use_cases/commands/sidebar_commands'
require_relative 'shoko/application/use_cases/commands/conditional_navigation_commands'
require_relative 'shoko/application/use_cases/commands/menu_commands'
require_relative 'shoko/application/use_cases/commands/annotation_editor_commands'
require_relative 'shoko/application/use_cases/commands/reader_commands'
require_relative 'shoko/adapters/state/actions/base_action'
require_relative 'shoko/adapters/state/actions/update_state_action'
require_relative 'shoko/adapters/state/actions/toggle_view_mode_action'
require_relative 'shoko/adapters/state/actions/switch_reader_mode_action'
require_relative 'shoko/adapters/state/actions/quit_to_menu_action'
require_relative 'shoko/adapters/state/actions/update_message_action'
require_relative 'shoko/adapters/state/actions/update_config_action'
require_relative 'shoko/adapters/state/actions/update_sidebar_action'
require_relative 'shoko/adapters/state/actions/update_rendered_lines_action'
require_relative 'shoko/adapters/state/actions/update_ui_loading_action'
require_relative 'shoko/adapters/state/actions/update_pagination_state_action'
require_relative 'shoko/adapters/state/actions/update_reader_meta_action'
require_relative 'shoko/adapters/state/actions/update_menu_action'

# Domain selectors for state access
require_relative 'shoko/adapters/state/selectors/reader_selectors'
require_relative 'shoko/adapters/state/selectors/menu_selectors'
require_relative 'shoko/adapters/state/selectors/config_selectors'

# Input system bridge (load after application commands)
require_relative 'shoko/adapters/input/command_bridge'

# UI layer
require_relative 'shoko/application/ui/view_models/reader_view_model'

# Application layer
require_relative 'shoko/application/unified_application'
require_relative 'shoko/application/ui/reader_view_model_builder'
require_relative 'shoko/application/reader_startup_orchestrator'
require_relative 'shoko/adapters/output/ui/rendering/frame_coordinator'
require_relative 'shoko/adapters/output/ui/rendering/render_pipeline'
require_relative 'shoko/core/services/pagination/page_info_calculator'
require_relative 'shoko/core/services/pagination/pagination_orchestrator'
require_relative 'shoko/core/services/pagination/pagination_coordinator'
require_relative 'shoko/adapters/output/ui/rendering/reader_render_coordinator'
require_relative 'shoko/application/reader_lifecycle'
require_relative 'shoko/core/services/progress_helper'

# Controller layer
require_relative 'shoko/application/controllers/ui_controller'
require_relative 'shoko/application/controllers/state_controller'
require_relative 'shoko/adapters/input/input_controller'

# Reading components
require_relative 'shoko/adapters/output/ui/components/reading/base_view_renderer'
require_relative 'shoko/adapters/output/ui/components/reading/split_view_renderer'
require_relative 'shoko/adapters/output/ui/components/reading/single_view_renderer'
require_relative 'shoko/adapters/output/ui/components/reading/help_renderer'
require_relative 'shoko/adapters/output/ui/components/reading/view_renderer_factory'

# Screen components
require_relative 'shoko/adapters/output/ui/components/screens/base_screen_component'
require_relative 'shoko/adapters/output/ui/components/screens/menu_screen_component'
require_relative 'shoko/adapters/output/ui/components/screens/annotation_detail_screen_component'
require_relative 'shoko/adapters/output/ui/components/screens/annotation_editor_screen_component'
require_relative 'shoko/adapters/output/ui/components/annotation_editor_overlay_component'

# UI components
require_relative 'shoko/application/controllers/menu_controller'
require_relative 'shoko/application/controllers/mouseable_reader'

# Application entry point
require_relative 'shoko/application/cli'

# Register supported ebook formats (all classes are loaded by this point)
Shoko::Core::BookFormats::FormatRegistry.register(
  '.epub',
  importer_class: Shoko::Adapters::BookSources::Epub::EpubImporter,
  metadata_extractor: Shoko::Core::BookFormats::Epub::MetadataExtractor,
  content_parser_factory: lambda { |raw, logger: nil|
    Shoko::Core::BookFormats::Epub::XHTMLContentParser.new(raw, logger: logger)
  }
)
Shoko::Core::BookFormats::FormatRegistry.register(
  '.fb2',
  importer_class: Shoko::Adapters::BookSources::Fb2::Fb2Importer,
  metadata_extractor: Shoko::Core::BookFormats::Fb2::Fb2MetadataExtractor,
  content_parser_factory: lambda { |raw, logger: nil|
    Shoko::Core::BookFormats::Fb2::Fb2ContentParser.new(raw, logger: logger)
  }
)
Shoko::Core::BookFormats::FormatRegistry.register(
  '.fb2.zip',
  importer_class: Shoko::Adapters::BookSources::Fb2::Fb2Importer,
  metadata_extractor: Shoko::Core::BookFormats::Fb2::Fb2MetadataExtractor,
  content_parser_factory: lambda { |raw, logger: nil|
    Shoko::Core::BookFormats::Fb2::Fb2ContentParser.new(raw, logger: logger)
  }
)
Shoko::Core::BookFormats::FormatRegistry.register(
  '.pdf',
  importer_class: Shoko::Adapters::BookSources::Pdf::PdfImporter,
  metadata_extractor: Shoko::Core::BookFormats::Pdf::PdfMetadataExtractor,
  content_parser_factory: lambda { |raw, logger: nil|
    Shoko::Core::BookFormats::Pdf::PdfContentParser.new(raw, logger: logger)
  }
)
# Kindle formats (MOBI, AZW, AZW3) — all share the PDB/Mobipocket container
%w[.mobi .azw .azw3].each do |ext|
  Shoko::Core::BookFormats::FormatRegistry.register(
    ext,
    importer_class: Shoko::Adapters::BookSources::Kindle::KindleImporter,
    metadata_extractor: Shoko::Core::BookFormats::Kindle::KindleMetadataExtractor,
    content_parser_factory: lambda { |raw, logger: nil|
      Shoko::Core::BookFormats::Kindle::KindleContentParser.new(raw, logger: logger)
    }
  )
end
# RTF format
Shoko::Core::BookFormats::FormatRegistry.register(
  '.rtf',
  importer_class: Shoko::Adapters::BookSources::Rtf::RtfImporter,
  metadata_extractor: Shoko::Core::BookFormats::Rtf::RtfMetadataExtractor,
  content_parser_factory: lambda { |raw, logger: nil|
    Shoko::Core::BookFormats::Rtf::RtfContentParser.new(raw, logger: logger)
  }
)

# Test-only shims and coverage warmup
if defined?(RSpec)
  require_relative 'shoko/test_support/test_mode'
  Shoko::TestSupport::TestMode.activate!
end

# Main module for the Shoko application
#
# This module serves as the namespace for all Shoko components
# and provides version information and error classes.
#
# @example Check version
#   puts Shoko::VERSION
#
# @example Handle errors
#   begin
#     Shoko::CLI.run
#   rescue Shoko::Error => e
#     puts "Error: #{e.message}"
#   end
module Shoko
end
