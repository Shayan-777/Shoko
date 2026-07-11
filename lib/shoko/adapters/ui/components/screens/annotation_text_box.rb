# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../ui/annotation_markup'
require_relative '../ui/box_drawer'
require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Text box helper for annotation screens.
          class AnnotationTextBox
            BOX_COLUMN = 2
            TEXT_COLUMN = 4
            BOX_SPACING = 2
            MIN_HEIGHT = 6
            BOTTOM_PADDING = 3

            attr_reader :row, :height, :width, :label, :text, :style

            def initialize(row:, height:, width:, label:, text:, style: :plain)
              @row = row
              @height = height
              @width = width
              @label = label
              @text = text.to_s
              @style = style
            end

            def inner_width
              width - 4
            end

            def frame_args
              {
                row: row,
                height: height,
                width: width,
                label: label,
              }
            end

            def each_visible_line(&block)
              return enum_for(__method__) unless block

              lines = if style == :markup
                        Ui::AnnotationMarkup::Styler.new(text).render_lines(inner_width)
                      else
                        Ui::TextUtils.wrap_text(text, inner_width)
                      end

              lines.first(max_lines).each_with_index(&block)
            end

            def render(context, drawer:, color_prefix:)
              drawer.draw_box(
                context.surface,
                context.bounds,
                Ui::BoxDrawer::BoxSpec.new(
                  row: row,
                  col: BOX_COLUMN,
                  height: height,
                  width: width
                ),
                label: label
              )
              render_lines(context, color_prefix: color_prefix)
            end

            def render_lines(context, color_prefix:)
              line_reset = Ui::AnnotationMarkup::STYLE_RESET

              each_visible_line do |line, index|
                display = style == :markup ? (line + line_reset) : line
                padded = Ui::TextUtils.pad_right(display, inner_width)
                context.surface.write(
                  context.bounds,
                  row + 1 + index,
                  TEXT_COLUMN,
                  "#{color_prefix}#{padded}#{context.reset}"
                )
              end
            end

            def cursor_position(cursor)
              return markup_cursor_position(cursor) if style == :markup

              plain_cursor_position(cursor)
            end

            def next_box(total_height:, label:, text:, style: nil)
              next_row = row + height + BOX_SPACING
              next_height = [total_height - next_row - BOTTOM_PADDING, MIN_HEIGHT].max
              AnnotationTextBox.new(
                row: next_row,
                height: next_height,
                width: width,
                label: label,
                text: text,
                style: style || @style
              )
            end

            private

            def max_lines
              [height - 2, 0].max
            end

            def markup_cursor_position(cursor)
              renderer = Ui::AnnotationMarkup::Styler.new(text)
              line_idx, col = renderer.cursor_position(cursor, inner_width)
              [row + 1 + line_idx, TEXT_COLUMN + col]
            end

            def plain_cursor_position(cursor)
              cursor_lines = Ui::TextUtils.wrap_text(text[0, cursor], inner_width)
              last_line = cursor_lines.last || ''
              cursor_row = row + 1 + [cursor_lines.length - 1, 0].max
              cursor_col = TEXT_COLUMN + Shoko::Shared::Terminal::TextMetrics.visible_length(last_line)
              [cursor_row, cursor_col]
            end
          end
        end
      end
    end
  end
end
