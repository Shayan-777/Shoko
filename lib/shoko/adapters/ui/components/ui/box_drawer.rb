# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Helper for drawing bordered boxes with optional labels.
          module BoxDrawer
            BoxSpec = Data.define(:row, :col, :height, :width)

            def draw_box(surface, bounds, box, label: nil)
              hline = '─' * (box.width - 2)
              surface.write(bounds, box.row, box.col, "╭#{hline}╮")
              write_box_label(surface, bounds, box, label) if label && box.width > 4
              draw_box_sides(surface, bounds, box)
              surface.write(bounds, box.row + box.height - 1, box.col, "╰#{hline}╯")
            end

            def write_box_label(surface, bounds, box, label)
              label_text = "[ #{label} ]"
              available = box.width - 3
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(
                label_text,
                available,
                start_column: bounds.x + box.col
              )
              surface.write(bounds, box.row, box.col + 2, clipped) unless clipped.empty?
            end

            def draw_box_sides(surface, bounds, box)
              (1...(box.height - 1)).each do |index|
                y_pos = box.row + index
                surface.write(bounds, y_pos, box.col, '│')
                surface.write(bounds, y_pos, box.col + box.width - 1, '│')
              end
            end
          end
        end
      end
    end
  end
end
