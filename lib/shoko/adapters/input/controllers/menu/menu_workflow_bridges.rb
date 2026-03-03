# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_workflow_runtime'
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
          # Adapter bridge for menu workflow UI/runtime operations.
          class MenuWorkflowRuntimeBridge
            include Shoko::Core::Ports::Outbound::MenuWorkflowRuntime

            def initialize(menu:, catalog:)
              @menu = menu
              @catalog = catalog
            end

            def draw_screen
              @menu.draw_screen
            end

            def refresh_scan(force:)
              @catalog.start_scan(force: force)
            end
          end

          # Adapter bridge for mode switching used by annotation workflows.
          class MenuModeSwitcherBridge
            include Shoko::Core::Ports::Outbound::MenuModeSwitcher

            def initialize(menu:)
              @menu = menu
            end

            def switch_mode(mode)
              @menu.switch_to_mode(mode)
            end
          end

          # Adapter bridge for reading selected annotation context.
          class AnnotationSelectionBridge
            include Shoko::Core::Ports::Outbound::AnnotationSelectionReader

            def initialize(menu:, logger: nil)
              @menu = menu
              @logger = logger
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

              Shoko::Core::Models::AnnotationSelection.from_h(annotation: annotation, book_path: book_path)
            end
          end

          # Adapter bridge for refreshing annotation view after mutations.
          class AnnotationViewRefreshBridge
            include Shoko::Core::Ports::Outbound::AnnotationViewRefresher

            def initialize(menu:, logger: nil)
              @menu = menu
              @logger = logger
            end

            def refresh_annotations_view
              @menu.refresh_annotations_view_for_workflow
            end
          end

          # Adapter bridge for launching reader by book path.
          class ReaderRunnerBridge
            include Shoko::Core::Ports::Outbound::ReaderRunner

            def initialize(menu:)
              @menu = menu
            end

            def run_reader(path)
              @menu.state_controller.run_reader(path)
            end
          end
        end
      end
    end
  end
end
