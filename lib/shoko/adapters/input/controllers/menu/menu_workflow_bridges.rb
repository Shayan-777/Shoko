# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_workflow_runtime'
require_relative '../../../../core/ports/outbound/menu_mode_switcher'
require_relative '../../../../core/ports/outbound/annotation_selection_reader'
require_relative '../../../../core/ports/outbound/annotation_view_refresher'
require_relative '../../../../core/ports/outbound/reader_runner'

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

            def initialize(selected_annotation_reader:, logger: nil)
              @selected_annotation_reader = selected_annotation_reader
              @logger = logger
            end

            def selected_annotation_and_path
              selection = @selected_annotation_reader.call
              if selection.is_a?(Array)
                [selection[0], selection[1]]
              elsif selection.is_a?(Hash)
                [selection[:annotation] || selection['annotation'],
                 selection[:book_path] || selection['book_path']]
              else
                [nil, nil]
              end
            # resilient-boundary
            rescue StandardError => e
              @logger&.debug('menu.annotation_selection_bridge.failed',
                             error: e.class.name,
                             message: e.message)
              [nil, nil]
            end
          end

          # Adapter bridge for refreshing annotation view after mutations.
          class AnnotationViewRefreshBridge
            include Shoko::Core::Ports::Outbound::AnnotationViewRefresher

            def initialize(refresh_annotations_view:, logger: nil)
              @refresh_annotations_view = refresh_annotations_view
              @logger = logger
            end

            def refresh_annotations_view
              @refresh_annotations_view.call
            # resilient-boundary
            rescue StandardError => e
              @logger&.error('menu.annotation_view_refresh_bridge.failed',
                             error: e.class.name,
                             message: e.message)
              nil
            end
          end

          # Adapter bridge for launching reader by book path.
          class ReaderRunnerBridge
            include Shoko::Core::Ports::Outbound::ReaderRunner

            def initialize(reader_runner:)
              @reader_runner = reader_runner
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
