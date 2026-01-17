# frozen_string_literal: true

require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Ui::Components
    module UI
      # Helper for drawing bordered boxes with optional labels.
      module BoxDrawer
        def draw_box(surface, bounds, row, col, height, width, label: nil)
          # Top border
          hline = '─' * (width - 2)
          surface.write(bounds, row, col, "╭#{hline}╮")
          if label && width > 4
            label_text = "[ #{label} ]"
            available = width - 3
            clipped = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(label_text, available,
                                                                                 start_column: bounds.x + col)
            surface.write(bounds, row, col + 2, clipped) unless clipped.empty?
          end
          # Sides
          (1...(height - 1)).each do |index|
            y_pos = row + index
            surface.write(bounds, y_pos, col, '│')
            surface.write(bounds, y_pos, col + width - 1, '│')
          end
          # Bottom
          surface.write(bounds, row + height - 1, col, "╰#{hline}╯")
        end
      end
    end
  end
end
