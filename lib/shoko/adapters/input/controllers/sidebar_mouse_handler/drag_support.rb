# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module SidebarMouseHandlerSupport
          # Handles dragging the sidebar scrollbar thumb and syncing TOC selection.
          module DragSupport
            private

            def start_sidebar_scroll_drag(terminal_coords, sidebar_bounds, sidebar_component)
              metrics = sidebar_component.toc_scroll_metrics(sidebar_bounds)
              return false unless metrics
              return false unless metrics.hit_scrollbar?(terminal_coords[:x], terminal_coords[:y])

              @sidebar_scroll_drag_active = true
              apply_sidebar_scroll_drag(metrics, terminal_coords[:y])
              draw_screen
              @mouse_handler.reset
              true
            end

            def handle_sidebar_scroll_drag(event, ctx)
              if event[:released]
                @sidebar_scroll_drag_active = false
                @mouse_handler.reset
                return true
              end

              return true unless drag_motion?(event) || event[:button].zero?

              metrics = ctx[:component].toc_scroll_metrics(ctx[:bounds])
              return true unless metrics

              apply_sidebar_scroll_drag(metrics, ctx[:coords][:y])
              draw_screen
              true
            end

            def apply_sidebar_scroll_drag(metrics, abs_row)
              full_index = metrics.full_index_for_abs_row(abs_row)
              return unless full_index

              ui_controller.select_sidebar_toc_index(full_index)
            end
          end
        end
      end
    end
  end
end
