# frozen_string_literal: true

require_relative '../../../shared/terminal/device'
require_relative '../../../shared/terminal/text_metrics'

module Shoko
  module Adapters::Ui::Components
    # Terminal wrapper that applies bounds and basic clipping
    class Surface
      def initialize(output = Terminal)
        @output = output
        @style_stack = []
      end

      # Write text at local (row, col) relative to bounds
      # Applies basic clipping to the provided bounds
      def write(bounds, row, col, text)
        b_height = bounds.height
        b_width  = bounds.width
        return if b_height <= 0 || b_width <= 0

        b_y = bounds.y
        b_x = bounds.x
        b_right = bounds.right
        b_bottom = bounds.bottom

        abs_row = b_y + row - 1
        abs_col = b_x + col - 1

        return if abs_row < b_y || abs_row > b_bottom
        return if abs_col < b_x || abs_col > b_right

        max_width = b_right - abs_col + 1
        clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(
          text.to_s,
          max_width,
          start_column: [abs_col - 1, 0].max
        )
        clipped = apply_dim(clipped) if dimmed?
        return if clipped.nil? || clipped.empty?

        @output.write(abs_row, abs_col, clipped)
      end

      # Write using absolute terminal coordinates while still clipping to bounds.
      #
      # This is intended for overlay components that operate in absolute
      # coordinates (e.g., mouse hit regions, selection geometry).
      def write_abs(bounds, abs_row, abs_col, text)
        local_row = abs_row.to_i - bounds.y + 1
        local_col = abs_col.to_i - bounds.x + 1
        write(bounds, local_row, local_col, text)
      end

      # Convenience to fill an area with a character
      def fill(bounds, char)
        w = bounds.width
        h = bounds.height
        line = char.to_s * w
        (0...h).each do |r|
          write(bounds, r + 1, 1, line)
        end
      end

      def with_dimmed
        @style_stack << :dim
        yield
      ensure
        @style_stack.pop
      end

      private

      def dimmed?
        @style_stack.include?(:dim)
      end

      def apply_dim(text)
        dim = Terminal::ANSI::DIM
        reset = Terminal::ANSI::RESET
        return text if text.empty?

        transformed = text.gsub(reset, "#{reset}#{dim}")
        "#{dim}#{transformed}#{reset}"
      end
    end
  end
end
