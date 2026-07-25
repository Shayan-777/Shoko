# frozen_string_literal: true

require_relative 'ui/bounds_geometry'
require 'shoko/shared/terminal/ansi'
require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        # Terminal wrapper that applies bounds and basic clipping
        class Surface
          def initialize(output)
            @output = output
            @style_stack = []
          end

          # Write text at local (row, col) relative to bounds
          # Applies basic clipping to the provided bounds
          def write(bounds, row, col, text)
            return unless writable_bounds?(bounds)

            abs_row, abs_col = Ui::BoundsGeometry.absolute_position(bounds, row, col)
            return unless within_bounds?(bounds, abs_row, abs_col)

            clipped = clipped_text(text, bounds, abs_col)
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

          def writable_bounds?(bounds)
            bounds.height.positive? && bounds.width.positive?
          end

          def within_bounds?(bounds, abs_row, abs_col)
            abs_row.between?(bounds.y, bounds.bottom) && abs_col.between?(bounds.x, bounds.right)
          end

          def clipped_text(text, bounds, abs_col)
            max_width = bounds.right - abs_col + 1
            clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(
              text.to_s,
              max_width,
              start_column: [abs_col - 1, 0].max
            )
            dimmed? ? apply_dim(clipped) : clipped
          end

          def dimmed?
            @style_stack.include?(:dim)
          end

          def apply_dim(text)
            dim = Shoko::Shared::Terminal::Ansi::DIM
            reset = Shoko::Shared::Terminal::Ansi::RESET
            return text if text.empty?

            transformed = text.gsub(reset, "#{reset}#{dim}")
            "#{dim}#{transformed}#{reset}"
          end
        end
      end
    end
  end
end
