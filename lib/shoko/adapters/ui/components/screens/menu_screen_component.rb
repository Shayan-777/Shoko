# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/layout'
require_relative '../menu_design/table_renderer'
require 'shoko/application/ports/inbound/menu_catalog'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Component-based renderer for the main menu screen
          class MenuScreenComponent < BaseScreenComponent
            MENU_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.main_menu_items

            def initialize(dependencies = nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              selected = menu_state_reader&.selected || 0
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: '')
              frame.render_divider

              render_menu_items(surface, bounds, selected)
            end

            private

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def render_menu_items(surface, bounds, selected)
              metrics = layout_metrics(bounds)
              table = MenuDesign::TableRenderer.new(surface, bounds)

              MENU_ITEMS.each_with_index do |item, index|
                row = metrics[:start_row] + index
                break if row >= metrics[:max_row]

                table.render_row(
                  row: row,
                  indent: metrics[:indent],
                  cells: [menu_item_text(item)],
                  widths: [metrics[:content_width]],
                  selected: index == selected
                )
              end
            end

            def layout_metrics(bounds)
              content_width = menu_content_width
              visual_width = content_width + selection_slot_width
              indent = MenuDesign::Layout.centered_indent(bounds, visual_width)
              start_row = MenuDesign::Layout.centered_row(
                bounds,
                top: 4,
                bottom: bounds.height - 2,
                content_rows: MENU_ITEMS.size
              )
              {
                indent: indent,
                content_width: content_width,
                start_row: start_row,
                max_row: bounds.height - 1,
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
