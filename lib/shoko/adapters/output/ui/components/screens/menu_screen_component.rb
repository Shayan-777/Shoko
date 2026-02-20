# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Component-based renderer for the main menu screen
      class MenuScreenComponent < BaseScreenComponent
        MenuItemCtx = Struct.new(:row, :item, :index, :selected, :indent, keyword_init: true)

        def initialize(observer_registry, dependencies = nil)
          super()
          @observer_registry = observer_registry
          @dependencies = dependencies
          @menu_state_reader = nil
          @observer_registry.add_observer(self, %i[menu selected])
        end

        MENU_ITEMS = [
          { icon: '󱉟', label: 'Browse Library' },
          { icon: '', label: 'Library' },
          { icon: '', label: 'Annotations' },
          { icon: '', label: 'Download Books' },
          { icon: '', label: 'Settings' },
          { icon: '', label: 'Quit' },
        ].freeze

        def do_render(surface, bounds)
          selected = menu_state_reader&.selected || 0

          render_menu_items(surface, bounds, selected)
        end

        private

        def menu_state_reader
          @menu_state_reader ||= @dependencies&.menu_state_reader
        end

        def render_menu_items(surface, bounds, selected)
          metrics = layout_metrics(bounds)

          MENU_ITEMS.each_with_index do |item, index|
            row = metrics[:start_row] + (index * metrics[:row_height])
            break if row >= metrics[:max_row]

            ctx = MenuItemCtx.new(row: row, item: item, index: index,
                                  selected: selected, indent: metrics[:indent])
            render_menu_item(surface, bounds, ctx)
          end
        end

        def render_menu_item(surface, bounds, ctx)
          item = ctx.item
          row = ctx.row
          indent = ctx.indent

          colors = row_colors(ctx.index == ctx.selected)

          surface.write(bounds, row, indent,
                        formatted_row(item[:icon], item[:label], colors))
        end

        def layout_metrics(bounds)
          height = bounds.height
          width  = bounds.width
          content_width = menu_content_width
          indent = ((width - content_width) / 2).floor
          indent = indent.clamp(2, [width - content_width, 0].max)
          row_height = 2
          {
            indent: indent,
            row_height: row_height,
            start_row: [(height - (MENU_ITEMS.size * row_height)) / 2, 4].max,
            max_row: height - 4,
          }
        end

        def formatted_row(icon, label, colors)
          icon_col = icon.to_s
          text = label
          "#{colors[:prefix]}#{colors[:fg]}#{icon_col}  #{text}#{Terminal::ANSI::RESET}"
        end

        def row_colors(selected)
          if selected
            {
              prefix: Terminal::ANSI::BOLD,
              fg: Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_ACCENT,
            }
          else
            {
              prefix: '',
              fg: Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_PRIMARY,
            }
          end
        end

        def menu_content_width
          max_label = MENU_ITEMS.map { |item| display_width(item[:label]) }.max
          icon_width = MENU_ITEMS.map { |item| display_width(item[:icon]) }.max
          icon_width + 2 + max_label
        end

        def display_width(text)
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
        end
      end
    end
  end
end
