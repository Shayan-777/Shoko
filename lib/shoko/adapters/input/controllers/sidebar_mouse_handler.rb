# frozen_string_literal: true

require_relative 'sidebar_mouse_handler/drag_support'
require_relative 'sidebar_mouse_handler/interaction_flow'
require_relative 'sidebar_mouse_handler/wheel_support'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles all sidebar-related mouse interactions.
        # Extracted from MouseableReader to reduce class size.
        module SidebarMouseHandler
          include SidebarMouseHandlerSupport::DragSupport
          include SidebarMouseHandlerSupport::InteractionFlow
          include SidebarMouseHandlerSupport::WheelSupport

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

          def mouse_wheel_delta(button)
            case button
            when 64 then -1
            when 65 then 1
            end
          end

          def update_toc_selection(index)
            ui_controller.set_sidebar_toc_selected(index)
            draw_screen
            @mouse_handler.reset
          end

          def drag_motion?(event)
            event[:button].anybits?(32)
          end

          def monotonic_time
            @clock_ref.monotonic_now
          end
        end
      end
    end
  end
end
