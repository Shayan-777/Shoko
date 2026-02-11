# frozen_string_literal: true

module Shoko
  module Application
    module Controllers
      # Handles all sidebar-related mouse interactions.
      # Extracted from MouseableReader to reduce class size.
      module SidebarMouseHandler
        SCROLL_WHEEL_STEP = 1
        SCROLL_WHEEL_COOLDOWN_SECONDS = 0.05

        private

        def handle_sidebar_mouse(event)
          return false if @mouse_handler.selecting

          ctx = sidebar_mouse_context(event)
          return false unless ctx

          return handle_sidebar_scroll_drag(event, ctx) if @sidebar_scroll_drag_active
          return false unless within_sidebar_bounds?(ctx)

          handle_sidebar_interaction(event, ctx)
        end

        def sidebar_mouse_context(event)
          coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
          height, width = terminal_service.size
          bounds = render_coordinator.sidebar_bounds(width, height)
          component = render_coordinator.sidebar_component
          return nil unless bounds && component

          { coords: coords, bounds: bounds, component: component }
        end

        def within_sidebar_bounds?(ctx)
          in_bounds = @coordinate_service.within_bounds?(
            ctx[:coords][:x], ctx[:coords][:y], ctx[:bounds]
          )
          @mouse_handler.reset unless in_bounds
          in_bounds
        end

        def handle_sidebar_interaction(event, ctx)
          coords, bounds, component = ctx.values_at(:coords, :bounds, :component)

          return true if handle_sidebar_wheel_if_applicable(event, coords, bounds, component)
          return true if handle_sidebar_drag_start(event, coords, bounds, component)
          return true if handle_sidebar_click(event, coords, bounds, component)

          @mouse_handler.reset
          true
        end

        def handle_sidebar_wheel_if_applicable(event, coords, bounds, component)
          delta = mouse_wheel_delta(event[:button])
          return false unless delta
          return true unless sidebar_wheel_event_allowed?(delta)

          handle_sidebar_wheel(delta, coords, bounds, component)
        end

        def handle_sidebar_drag_start(event, coords, bounds, component)
          event[:button].zero? && !event[:released] &&
            start_sidebar_scroll_drag(coords, bounds, component)
        end

        def handle_sidebar_click(event, coords, bounds, component)
          return false unless event[:released] && event[:button].zero?

          handle_sidebar_tab_click(coords, bounds, component) ||
            handle_sidebar_toc_click(coords, bounds, component)
        end

        def handle_sidebar_tab_click(coords, bounds, component)
          tab = component.tab_for_point(coords[:x], coords[:y], bounds)
          return false unless tab

          ui_controller.activate_sidebar_tab(tab)
          draw_screen
          @mouse_handler.reset
          true
        end

        def handle_sidebar_toc_click(coords, bounds, component)
          toc_item = component.toc_entry_at(coords[:x], coords[:y], bounds)
          return false unless toc_item && ui_controller.respond_to?(:handle_sidebar_toc_click)

          ui_controller.handle_sidebar_toc_click(toc_item.full_index)
          draw_screen
          true
        end

        def mouse_wheel_delta(button)
          case button
          when 64 then -1
          when 65 then 1
          end
        end

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
             (now - last_time) < SCROLL_WHEEL_COOLDOWN_SECONDS
            return false
          end

          @sidebar_wheel_last_applied_at = now
          @sidebar_wheel_last_applied_delta = delta
          true
        end

        def wheel_scroll_target(metrics, indices, delta)
          current_pos = current_nav_position(metrics, indices)
          step = SCROLL_WHEEL_STEP * delta
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

        def update_toc_selection(index)
          if ui_controller.respond_to?(:set_sidebar_toc_selected)
            ui_controller.set_sidebar_toc_selected(index)
          else
            @state_writer.update_sidebar(toc_selected: index)
          end
          draw_screen
          @mouse_handler.reset
        end

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

        def drag_motion?(event)
          event[:button].anybits?(32)
        end

        def apply_sidebar_scroll_drag(metrics, abs_row)
          full_index = metrics.full_index_for_abs_row(abs_row)
          return unless full_index

          if ui_controller.respond_to?(:set_sidebar_toc_selected)
            ui_controller.set_sidebar_toc_selected(full_index)
          else
            @state_writer.update_sidebar(toc_selected: full_index)
          end
        end

        def monotonic_time
          @clock_ref ? @clock_ref.monotonic_now : Time.now.to_f
        end
      end
    end
  end
end
