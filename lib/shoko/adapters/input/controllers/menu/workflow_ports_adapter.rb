# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/catalog_refresh_control'
require_relative '../../../../core/ports/outbound/menu_mode_switcher'
require_relative '../../../../core/ports/outbound/annotation_selection_reader'
require_relative '../../../../core/ports/outbound/annotation_view_refresher'
require_relative '../../../../core/ports/outbound/reader_runner'
require_relative '../../../../core/models/annotation_selection'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Consolidated menu adapter for non-launch workflow ports.
          class WorkflowPortsAdapter
            include Shoko::Core::Ports::Outbound::CatalogRefreshControl
            include Shoko::Core::Ports::Outbound::MenuModeSwitcher
            include Shoko::Core::Ports::Outbound::AnnotationSelectionReader
            include Shoko::Core::Ports::Outbound::AnnotationViewRefresher
            include Shoko::Core::Ports::Outbound::ReaderRunner

            def initialize(menu:, catalog:, reader_runner:)
              raise ArgumentError, 'reader_runner is required' if reader_runner.nil?

              @menu = menu
              @catalog = catalog
              @reader_runner = reader_runner
            end

            def refresh_catalog(force:)
              @catalog.start_scan(force: force)
            end

            def switch_mode(mode)
              @menu.switch_to_mode(mode)
            end

            def selected_annotation
              selection = @menu.selected_annotation_for_workflow
              return nil if selection.nil?
              unless selection.is_a?(Hash)
                raise ArgumentError, "selected_annotation_for_workflow must return Hash, got #{selection.class}"
              end

              annotation = selection[:annotation]
              book_path = selection[:book_path]
              return nil unless annotation && book_path

              Shoko::Core::Models::AnnotationSelection.from_h(
                annotation: annotation,
                book_path: book_path
              )
            end

            def refresh_annotations_view
              @menu.refresh_annotations_view_for_workflow
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
