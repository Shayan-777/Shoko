# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module ReaderActions
              def show_annotations_overlay
                controller.open_annotations
              end

              def show_help_overlay
                controller.show_help
              end

              def hide_help_overlay
                controller.switch_mode(:read)
              end

              def toggle_view_mode
                controller.toggle_view_mode
              end

              def toggle_page_numbering_mode
                controller.toggle_page_numbering_mode
              end

              def adjust_line_spacing(delta:)
                delta.negative? ? controller.decrease_line_spacing : controller.increase_line_spacing
              end

              def rebuild_pagination
                controller.rebuild_pagination
              end

              def clear_pagination_cache
                controller.invalidate_pagination_cache
              end

              def return_to_menu
                controller.quit_to_menu
              end

              def quit_application
                controller.quit_application
              end
            end
          end
        end
      end
    end
  end
end
