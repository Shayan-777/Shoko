# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Adapter-owned helper that exposes blended backdrop glyphs for overlays.
          class BackdropOverlay
            def initialize(rendered_lines: nil)
              @backdrop_rows_key = nil
              @backdrop_rows = {}
              update_rendered_lines(rendered_lines)
            end

            def update_rendered_lines(rendered_lines)
              @rendered_lines = rendered_lines.is_a?(Hash) ? rendered_lines : {}
              @backdrop_rows_key = nil
              @backdrop_rows = {}
            end

            def segment(row, col, width)
              normalized_width = width.to_i
              return '' if normalized_width <= 0

              build_segment(row, col, normalized_width)
            end

            private

            def build_segment(row, col, width)
              cell_map = backdrop_cells_for_row(row)
              col_start = col.to_i
              col_end = col_start + width
              (col_start...col_end).map do |column|
                value = cell_map[column]
                next ' ' if value.nil? || value == :continuation

                backdrop_char(value)
              end.join
            end

            def backdrop_char(value)
              char = value.to_s
              return ' ' if char.empty? || char == ' '

              char
            end

            def backdrop_cells_for_row(row)
              cache = backdrop_row_cache
              return cache[row] if cache.key?(row)

              cache[row] = build_backdrop_cells(row)
            end

            def build_backdrop_cells(row)
              geometries_for_row(row).each_with_object({}) do |geometry, cells|
                merge_geometry_cells(cells, geometry)
              end
            end

            def geometries_for_row(row)
              return [] unless @rendered_lines.is_a?(Hash)

              geometries = @rendered_lines.each_value.filter_map { |entry| row_geometry(entry, row) }

              geometries.sort_by { |geometry| geometry.column_origin.to_i }
            end

            def row_geometry(entry, row)
              return nil unless entry.respond_to?(:[])

              geometry = entry[:geometry]
              return nil unless geometry
              return nil unless geometry.respond_to?(:row) && geometry.respond_to?(:column_origin)
              return nil unless geometry.row.to_i == row.to_i

              geometry
            end

            def merge_geometry_cells(cells, geometry)
              Array(geometry.cells).each do |cell|
                merge_cell(cells, geometry, cell)
              end
            end

            def merge_cell(cells, geometry, cell)
              unless cell.respond_to?(:display_width) && cell.respond_to?(:screen_x) && cell.respond_to?(:cluster)
                return
              end

              width = cell.display_width.to_i
              return if width <= 0

              absolute_column = geometry.column_origin.to_i + cell.screen_x.to_i
              cluster = cell.cluster.to_s
              cells[absolute_column] = cluster.empty? ? ' ' : cluster
              mark_continuation_cells(cells, absolute_column, width)
            end

            def mark_continuation_cells(cells, absolute_column, width)
              1.upto(width - 1) do |delta|
                cells[absolute_column + delta] = :continuation
              end
            end

            def backdrop_row_cache
              key = @rendered_lines.object_id
              return @backdrop_rows if @backdrop_rows_key == key

              @backdrop_rows_key = key
              @backdrop_rows = {}
            end
          end
        end
      end
    end
  end
end
