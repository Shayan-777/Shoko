# frozen_string_literal: true

require_relative '../../../../application/ports/outbound/catalog_refresh_control'
require_relative '../../../../application/ports/outbound/menu_mode_switcher'
require_relative '../../../../application/ports/outbound/annotation_selection_reader'
require_relative '../../../../application/ports/outbound/annotation_view_refresher'
require_relative '../../../../application/ports/outbound/reader_runner'
require_relative '../../../../core/models/annotation_selection'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Consolidated menu adapter for non-launch workflow ports.
          class WorkflowPortsAdapter
            include Shoko::Application::Ports::Outbound::CatalogRefreshControl
            include Shoko::Application::Ports::Outbound::MenuModeSwitcher
            include Shoko::Application::Ports::Outbound::AnnotationSelectionReader
            include Shoko::Application::Ports::Outbound::AnnotationViewRefresher
            include Shoko::Application::Ports::Outbound::ReaderRunner

            def initialize(catalog:, mode_switcher:, annotations_screen:, reader_runner:)
              raise ArgumentError, 'reader_runner is required' if reader_runner.nil?

              @catalog = catalog
              @mode_switcher = mode_switcher
              @annotations_screen = annotations_screen
              @reader_runner = reader_runner
            end

            def refresh_catalog(force:)
              @catalog.start_scan(force: force)
            end

            def switch_mode(mode)
              @mode_switcher.call(mode)
            end

            def selected_annotation
              annotation = @annotations_screen.current_annotation
              book_path = @annotations_screen.current_book_path
              return nil unless annotation && book_path

              Shoko::Core::Models::AnnotationSelection.from_h(annotation: annotation, book_path: book_path)
            end

            def refresh_annotations_view
              @annotations_screen.refresh_data
            end

            def run_reader(path)
              @reader_runner.call(path)
            end
          end
        end
      end
    end
  end
end
