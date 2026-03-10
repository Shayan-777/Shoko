# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module SidebarMouseHandlerSupport
          module WheelSupport
            private

            def handle_sidebar_wheel(delta, terminal_coords, sidebar_bounds, sidebar_component)
              metrics = sidebar_component.toc_scroll_metrics(sidebar_bounds)
              return false unless metrics&.row_in_track?(terminal_coords[:y])

              indices = metrics.navigable_indices
              return false if indices.empty?

              target = wheel_scroll_target(metrics, indices, delta)
              update_toc_selection(target)
              true
            end

            def sidebar_wheel_event_allowed?(delta)
              now = monotonic_time
              last_time = @sidebar_wheel_last_applied_at
              last_delta = @sidebar_wheel_last_applied_delta

              if last_time && last_delta == delta &&
                 (now - last_time) < SidebarMouseHandler::SCROLL_WHEEL_COOLDOWN_SECONDS
                return false
              end

              @sidebar_wheel_last_applied_at = now
              @sidebar_wheel_last_applied_delta = delta
              true
            end

            def wheel_scroll_target(metrics, indices, delta)
              current_pos = current_nav_position(metrics, indices)
              step = SidebarMouseHandler::SCROLL_WHEEL_STEP * delta
              target_pos = (current_pos + step).clamp(0, indices.length - 1)
              indices[target_pos]
            end

            def current_nav_position(metrics, indices)
              current_full = metrics.selected_full_index || indices.first
              pos = metrics.nav_position_for(current_full)

              if pos.nil? && metrics.selected_visible_index
                fallback = metrics.visible_indices[metrics.selected_visible_index]
                pos = metrics.nav_position_for(fallback)
              end

              pos || 0
            end
          end
        end
      end
    end
  end
end
