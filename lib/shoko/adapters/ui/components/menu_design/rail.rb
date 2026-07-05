# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative '../status_bar/palette'
require_relative 'icon_set'
require_relative 'view_accents'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # The app shell's left compartment: a full-height rail on the bar's
          # slate, so the rail and the bottom status bar read as one continuous
          # chrome around the elevated canvas. The SHOKO wordmark sits at the
          # top; the menu entries hang left-aligned beneath it in small groups
          # (shelf · sources · system). On the landing screen the highlighted
          # entry takes the family's selection treatment — selection strip,
          # brand-blue pointer, signature-accent icon — and inside a view the
          # same treatment marks where you are. Every entry registers itself
          # with the hit registry, so the rail is the app's clickable sidebar.
          class Rail
            Palette = StatusBar::Palette
            TextMetrics = Shoko::Shared::Terminal::TextMetrics

            LEFT_PAD = 1
            RIGHT_PAD = 2
            ICON_GAP = 2
            BRAND_ROW = 2
            ITEMS_START_ROW = 5
            # A breathing row after these entries splits the rail into its
            # three clusters without drawing a single line.
            GROUP_BREAK_AFTER = %i[annotations translator].freeze

            def self.content_width(items)
              icon_col = icon_column_width(items)
              label_max = items.map { |item| TextMetrics.visible_length(item.label.to_s) }.max.to_i
              LEFT_PAD + pointer_width + icon_col + ICON_GAP + label_max + RIGHT_PAD
            end

            def self.icon_column_width(items)
              items.map { |item| TextMetrics.visible_length(IconSet.icon_for(item.icon_key)) }.max.to_i
            end

            def self.pointer_width
              TextMetrics.visible_length(IconSet.selection_pointer)
            end

            def initialize(surface, bounds, width:, items:, hits: nil)
              @surface = surface
              @bounds = bounds
              @width = width
              @items = items
              @hits = hits
            end

            # The whole-rail region registers first so the per-item regions
            # (registered later while rows render) win the reverse hit search.
            def render(selected:)
              paint_surface
              register_wheel_region
              render_brand
              render_items(selected)
            end

            private

            def paint_surface
              blank = "#{Palette::RESET}#{Palette::LANDING_RAIL_BG}#{' ' * @width}#{Palette::RESET}"
              (1..@bounds.height).each { |row| @surface.write(@bounds, row, 1, blank) }
            end

            def render_brand
              brand = "#{Palette::RESET}#{Palette::LANDING_RAIL_BG}#{Palette.fg(Palette::BRAND_RGB)}" \
                      "#{Palette::BOLD}SHOKO#{Palette::RESET}"
              @surface.write(@bounds, BRAND_ROW, 1 + LEFT_PAD + self.class.pointer_width, brand)
            end

            def render_items(selected)
              icon_col = self.class.icon_column_width(@items)
              row = items_start_row
              @items.each_with_index do |item, index|
                break if row > @bounds.height

                @surface.write(@bounds, row, 1, item_row(item, index, icon_col, selected: index == selected))
                register_item(row, index)
                row += 1
                row += 1 if group_gaps? && GROUP_BREAK_AFTER.include?(item.key)
              end
            end

            # Group gaps are dropped (and the block starts higher) only when
            # the rail would otherwise run out of rows.
            def items_start_row
              group_gaps? ? ITEMS_START_ROW : [BRAND_ROW + 2, 3].max
            end

            def group_gaps?
              ITEMS_START_ROW + @items.length + GROUP_BREAK_AFTER.length - 1 <= @bounds.height
            end

            def item_row(item, index, icon_col, selected:)
              background = item_background(index, selected)
              cells = [
                ' ' * LEFT_PAD,
                pointer_cell(selected),
                icon_cell(item, icon_col, selected),
                label_cell(item, selected),
              ]
              text = cells.map { |cell| "#{Palette::RESET}#{background}#{cell}" }.join
              "#{text}#{Palette::RESET}#{background}#{trailing_pad(cells)}#{Palette::RESET}"
            end

            def item_background(index, selected)
              return Palette::LANDING_SELECTED_BG if selected
              return Palette::LIST_HOVER_BG if hover_item?(index)

              Palette::LANDING_RAIL_BG
            end

            def pointer_cell(selected)
              pointer = IconSet.selection_pointer
              return "#{Palette::LANDING_POINTER_FG}#{pointer}" if selected

              ' ' * self.class.pointer_width
            end

            def icon_cell(item, icon_col, selected)
              icon = IconSet.icon_for(item.icon_key)
              pad = ' ' * (icon_col - TextMetrics.visible_length(icon) + ICON_GAP)
              foreground = selected ? ViewAccents.for(item.key) : Palette::LANDING_FAINT_FG
              "#{foreground}#{icon}#{pad}"
            end

            def label_cell(item, selected)
              foreground = selected ? Palette::LANDING_TITLE_FG : Palette::TEXT_FG
              "#{foreground}#{item.label}"
            end

            def trailing_pad(cells)
              used = cells.sum { |cell| TextMetrics.visible_length(cell) }
              ' ' * [@width - used, 0].max
            end

            def item_screen_row(index)
              row = items_start_row + index
              return row unless group_gaps?

              gaps_before = GROUP_BREAK_AFTER.count do |key|
                break_index = @items.index { |item| item.key == key }
                break_index && break_index < index
              end
              row + gaps_before
            end

            def hover_item?(index)
              return false unless @hits

              @hits.hover?(
                col: @bounds.x, row: @bounds.y + item_screen_row(index) - 1,
                width: @width, height: 1
              )
            end

            def register_item(row, index)
              @hits&.register(
                col: @bounds.x, row: @bounds.y + row - 1,
                width: @width, height: 1,
                action: { type: :rail, index: index }
              )
            end

            def register_wheel_region
              @hits&.register(
                col: @bounds.x, row: @bounds.y,
                width: @width, height: @bounds.height,
                action: { type: :rail_surface }
              )
            end
          end
        end
      end
    end
  end
end
