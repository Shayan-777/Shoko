# frozen_string_literal: true

require_relative 'backdrop_cell_map'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Adapter-owned helper that exposes blended backdrop glyphs for overlays.
          class BackdropOverlay
            def initialize(rendered_lines: nil)
              @cell_map = BackdropCellMap.new(rendered_lines: rendered_lines)
            end

            def update_rendered_lines(rendered_lines)
              @cell_map.update_rendered_lines(rendered_lines)
            end

            def segment(row, col, width)
              normalized_width = width.to_i
              return '' if normalized_width <= 0

              build_segment(row, col, normalized_width)
            end

            private

            def build_segment(row, col, width)
              cells = @cell_map.cells_for_row(row)
              col_start = col.to_i
              col_end = col_start + width
              (col_start...col_end).map do |column|
                value = cells[column]
                next ' ' if value.nil? || value == :continuation

                backdrop_char(value)
              end.join
            end

            def backdrop_char(value)
              char = value.to_s
              return ' ' if char.empty? || char == ' '

              char
            end
          end
        end
      end
    end
  end
end
