# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Maps a rendered-line registry onto the backdrop glyphs occupying
          # each screen column of a row, so an overlay can show what it covers.
          #
          # Owns the derived-row cache, invalidated whenever the underlying
          # rendered lines are replaced. Two overlays consume it — the general
          # BackdropOverlay and the popup menu, which attenuates the glyphs it
          # draws over — so it is a collaborator rather than a helper copied
          # into both (constitution R1/R3).
          class BackdropCellMap
            def initialize(rendered_lines: nil)
              @rows_key = nil
              @rows = {}
              update_rendered_lines(rendered_lines)
            end

            def update_rendered_lines(rendered_lines)
              @rendered_lines = rendered_lines.is_a?(Hash) ? rendered_lines : {}
              @rows_key = nil
              @rows = {}
            end

            # @param row [Integer] absolute screen row
            # @return [Hash{Integer => String, Symbol}] column => cluster, or
            #   :continuation for columns covered by a wide glyph
            def cells_for_row(row)
              cache = row_cache
              return cache[row] if cache.key?(row)

              cache[row] = build_cells(row)
            end

            private

            def build_cells(row)
              geometries_for_row(row).each_with_object({}) do |geometry, cells|
                merge_geometry_cells(cells, geometry)
              end
            end

            def geometries_for_row(row)
              geometries = @rendered_lines.each_value.filter_map { |entry| row_geometry(entry, row) }

              geometries.sort_by { |geometry| geometry.column_origin.to_i }
            end

            # The registry is a plain state-owned Hash of heterogeneous render
            # entries, so shape probing here is a genuine polymorphic boundary
            # rather than a contract the ports pin.
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

            def row_cache
              key = @rendered_lines.object_id
              return @rows if @rows_key == key

              @rows_key = key
              @rows = {}
            end
          end
        end
      end
    end
  end
end
