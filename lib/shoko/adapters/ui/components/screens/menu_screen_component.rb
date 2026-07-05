# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/layout'
require_relative '../menu_design/canvas_frame'
require_relative '../status_bar/palette'
require_relative 'landing/layout'
require_relative 'landing/preview_content'
require_relative 'landing/preview_panel'
require 'shoko/application/ports/inbound/menu_catalog'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # The landing menu — the canvas half of the app's home screen.
          #
          # The shell (MainMenuComponent) owns the rail; beside it this screen
          # renders the live preview of whichever rail entry is highlighted, in
          # the shared canvas grammar. When the shell hides the rail on narrow
          # terminals it renders the compact centered list instead.
          class MenuScreenComponent < BaseScreenComponent
            MENU_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.main_menu_items

            # Set by the shell each frame: true when the rail is visible and
            # these bounds are the preview canvas.
            attr_writer :canvas_mode

            def initialize(dependencies = nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @canvas_mode = nil
              @preview_content = Landing::PreviewContent.new(dependencies)
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

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            # Standalone renders (specs, tooling) fall back to the same
            # breakpoint the shell uses.
            def canvas_mode?(bounds)
              return @canvas_mode unless @canvas_mode.nil?

              Landing::Layout.wide?(bounds)
            end

            def render_preview(surface, bounds, selected)
              preview = @preview_content.build(MENU_ITEMS[selected].key, rows: preview_row_budget(bounds))
              Landing::PreviewPanel.new(surface, bounds).render(preview)
            end

            def preview_row_budget(bounds)
              [bounds.height - MenuDesign::CanvasFrame::BODY_TOP - 1, 3].max
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
              palette = StatusBar::Palette
              return "#{' ' * selection_slot_width}#{menu_item_text(item)}" unless selected

              "#{palette::RESET}#{palette::LANDING_POINTER_FG}#{MenuDesign::IconSet.selection_pointer}" \
                "#{palette::RESET}#{palette::BOLD}#{menu_item_text(item)}#{palette::RESET}"
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
