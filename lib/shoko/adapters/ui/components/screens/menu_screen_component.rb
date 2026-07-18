# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/layout'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative 'landing/layout'
require 'shoko/application/ports/inbound/menu_catalog'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # The landing menu — the canvas half of the app's home screen.
          #
          # The shell (MainMenuComponent) owns the rail; beside it this screen
          # renders a live preview of whichever rail entry is highlighted. The
          # preview IS the real destination view, rendered read-only on the
          # shared canvas, so the landing screen shows the true site behind each
          # entry rather than a stand-in. Quit has no view, so it shows a
          # farewell card. When the shell hides the rail on narrow terminals
          # this screen renders the compact centered list instead.
          class MenuScreenComponent < BaseScreenComponent
            MENU_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.main_menu_items
            Palette = StatusBar::Palette

            # Set by the shell each frame: true when the rail is visible and
            # these bounds are the preview canvas.
            attr_writer :canvas_mode

            # +preview_screen_provider+ maps a rail entry key to the real screen
            # component that opening it renders (nil for entries with no view,
            # e.g. Quit). The shell injects it so this screen can render the
            # true destination view as the preview.
            def initialize(menu_state_reader: nil, menu_hit_registry: nil, menu_visual_profile: nil,
                           preview_screen_provider: nil)
              super()
              @menu_state_reader = menu_state_reader
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
              @canvas_mode = nil
              @preview_screen_provider = preview_screen_provider
            end

            def do_render(surface, bounds)
              selected = (menu_state_reader&.selected || 0).to_i.clamp(0, MENU_ITEMS.length - 1)
              if canvas_mode?(bounds)
                render_preview(surface, bounds, selected)
              else
                render_compact(surface, bounds, selected)
              end
            end

            private

            attr_reader :menu_state_reader

            # Standalone renders (specs, tooling) fall back to the same
            # breakpoint the shell uses.
            def canvas_mode?(bounds)
              return @canvas_mode unless @canvas_mode.nil?

              Landing::Layout.wide?(bounds)
            end

            # ----- live preview: the highlighted entry's real destination view -----

            # Render the actual view for the highlighted entry so the canvas
            # shows exactly what opening it will show. It renders read-only: the
            # view's row/wheel hit regions are dropped for the frame so only the
            # rail stays interactive under the pointer.
            def render_preview(surface, bounds, selected)
              item = MENU_ITEMS[selected]
              screen = @preview_screen_provider&.call(item.key)
              return render_farewell(surface, bounds, item) unless screen

              registry = hit_registry
              return screen.render(surface, bounds) unless registry

              registry.suspend { screen.render(surface, bounds) }
            end

            # Entries with no destination view (Quit) get a farewell on the same
            # canvas grammar; the degenerate no-provider case shows a bare card.
            def render_farewell(surface, bounds, item)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              return if frame.content_width < 8

              frame.render_rule(title: item.label, accent: MenuDesign::ViewAccents.for(item.key))
              render_farewell_body(frame) if item.key == :quit
              frame.render_hint(item.key == :quit ? 'ENTER quit' : 'ENTER opens')
            end

            def render_farewell_body(frame)
              dim = Palette::LANDING_DIM_FG
              lines = [
                ['Close Shoko.', nil],
                ['', nil],
                ['Progress, bookmarks and annotations are', dim],
                ['saved automatically. See you next chapter.', dim],
              ]
              lines.each_with_index do |(text, foreground), offset|
                row = frame.body_top + offset
                break if row > frame.body_bottom

                frame.write_line(row, [[text, foreground]])
              end
            end

            def hit_registry
              @menu_hit_registry
            end

            # ----- compact fallback (small terminals) -----

            def render_compact(surface, bounds, selected)
              metrics = compact_layout_metrics(bounds)

              MENU_ITEMS.each_with_index do |item, index|
                row = metrics[:start_row] + index
                break if row >= metrics[:max_row]

                surface.write(bounds, row, metrics[:indent],
                              compact_row(item, selected: index == selected))
              end
            end

            # Compact rows sit on the terminal's own background (no canvas),
            # so only the selection takes color: brand-blue pointer + bold.
            def compact_row(item, selected:)
              return "#{' ' * selection_slot_width}#{menu_item_text(item)}" unless selected

              "#{Palette::RESET}#{Palette::LANDING_POINTER_FG}#{MenuDesign::IconSet.selection_pointer}" \
                "#{Palette::RESET}#{Palette::BOLD}#{menu_item_text(item)}#{Palette::RESET}"
            end

            def compact_layout_metrics(bounds)
              content_width = menu_content_width
              visual_width = content_width + selection_slot_width
              indent = MenuDesign::Layout.centered_indent(bounds, visual_width)
              start_row = MenuDesign::Layout.centered_row(
                bounds,
                top: 2,
                bottom: bounds.height - 1,
                content_rows: MENU_ITEMS.size
              )
              {
                indent: indent,
                content_width: content_width,
                start_row: start_row,
                max_row: bounds.height + 1,
              }
            end

            def menu_content_width
              MENU_ITEMS.map { |item| display_width(menu_item_text(item)) }.max
            end

            def selection_slot_width
              display_width(MenuDesign::IconSet.selection_pointer)
            end

            def menu_item_text(item)
              icon = MenuDesign::IconSet.icon_for(item.icon_key)
              return item.label if icon.empty?

              "#{icon}  #{item.label}"
            end

            def display_width(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end
          end
        end
      end
    end
  end
end
