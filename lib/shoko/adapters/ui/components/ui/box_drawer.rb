# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Helper for drawing bordered boxes with optional labels.
          module BoxDrawer
            BoxSpec = Data.define(:row, :col, :height, :width)

            def draw_box(surface, bounds, box, label: nil, border_color: nil, label_color: nil)
              draw_box_edges(surface, bounds, box, border_color)
              if label && box.width > 4
                write_box_label(surface, bounds, box, label: label, color: label_color || border_color)
              end
              draw_box_sides(surface, bounds, box, border_color)
            end

            def write_box_label(surface, bounds, box, label:, color: nil)
              label_text = "[ #{label} ]"
              available = box.width - 3
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(
                label_text,
                available,
                start_column: bounds.x + box.col
              )
              surface.write(bounds, box.row, box.col + 2, colorize_box_text(clipped, color)) unless clipped.empty?
            end

            def draw_box_sides(surface, bounds, box, border_color)
              (1...(box.height - 1)).each do |index|
                y_pos = box.row + index
                surface.write(bounds, y_pos, box.col, colorize_box_text('│', border_color))
                surface.write(bounds, y_pos, box.col + box.width - 1, colorize_box_text('│', border_color))
              end
            end

            def draw_box_edges(surface, bounds, box, border_color)
              hline = '─' * (box.width - 2)
              surface.write(bounds, box.row, box.col, colorize_box_text("╭#{hline}╮", border_color))
              surface.write(
                bounds,
                box.row + box.height - 1,
                box.col,
                colorize_box_text("╰#{hline}╯", border_color)
              )
            end

            def colorize_box_text(text, color)
              prefix = color.to_s
              return text if prefix.empty?

              "#{prefix}#{text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end
          end
        end
      end
    end
  end
end
