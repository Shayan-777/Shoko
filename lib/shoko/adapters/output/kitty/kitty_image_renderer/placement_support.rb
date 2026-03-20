# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Kitty
        class KittyImageRenderer
          # Screen placement and virtual-placement registry behavior.
          module PlacementSupport
            private

            def place_rendered_image(request)
              fit = fit_geometry(request[:image_id], request[:cols], request[:rows])
              sequence = KittyGraphics.place(
                request[:image_id],
                placement_id: normalized_placement_id(request),
                cols: fit[:cols],
                rows: fit[:rows],
                quiet: true,
                z: request[:z]
              )
              emit_positioned_sequence(request, fit, sequence)
              request[:image_id]
            end

            def ensure_virtual_placement(request)
              placement = normalized_virtual_placement(request)
              return nil unless placement
              return placement[:key] if @virtual_placements[placement[:key]]

              sequence = KittyGraphics.virtual_place(
                placement[:image_id],
                cols: placement[:cols],
                rows: placement[:rows],
                placement_id: placement[:placement_id],
                quiet: true,
                z: placement[:z]
              )
              emit_raw(placement[:output], sequence)
              @virtual_placements[placement[:key]] = true
              placement[:key]
            end

            def emit_positioned_sequence(request, fit, sequence)
              abs_row = request[:row].to_i + fit[:row_offset]
              abs_col = request[:col].to_i + fit[:col_offset]
              emit_raw(request[:output], TerminalOutput::ANSI.move(abs_row, abs_col) + sequence)
            end

            def normalized_virtual_placement(request)
              cols_i = request[:cols].to_i
              rows_i = request[:rows].to_i
              return nil if cols_i <= 0 || rows_i <= 0

              {
                output: request[:output],
                image_id: request[:image_id],
                cols: cols_i,
                rows: rows_i,
                placement_id: normalized_placement_id(request),
                z: request[:z],
                key: placement_cache_key_for(request, cols_i, rows_i),
              }
            end

            def normalized_placement_id(request)
              raw = request[:placement_id].to_i
              return nil unless raw.positive?

              clamp_id(raw)
            end

            def emit_raw(output, sequence)
              output.raw(sequence)
            end

            def clamp_id(value)
              int = value.to_i
              int = 1 if int <= 0
              if int > MAX_ID
                int %= MAX_ID
                int = 1 if int.zero?
              end
              int
            end

            def placement_cache_key(image_id:, placement_id:, cols:, rows:, depth:)
              [image_id.to_i, placement_id.to_i, cols.to_i, rows.to_i, depth&.to_i]
            end

            def placement_cache_key_for(request, cols_i, rows_i)
              placement_cache_key(
                image_id: request[:image_id],
                placement_id: normalized_placement_id(request),
                cols: cols_i,
                rows: rows_i,
                depth: request[:z]
              )
            end
          end
        end
      end
    end
  end
end
