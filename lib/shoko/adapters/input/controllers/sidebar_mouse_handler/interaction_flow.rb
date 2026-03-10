# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module SidebarMouseHandlerSupport
          module InteractionFlow
            private

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
              return false unless toc_item

              ui_controller.handle_sidebar_toc_click(toc_item.full_index)
              draw_screen
              true
            end
          end
        end
      end
    end
  end
end
