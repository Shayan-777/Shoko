# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Kitty
        class KittyImageRenderer
          # Image-dimension probing and terminal-cell geometry fitting.
          module GeometrySupport
            private

            def fit_geometry(image_id, max_cols, max_rows)
              cols_i, rows_i = normalized_fit_limits(max_cols, max_rows)
              dims = normalized_dimensions(image_id)
              return default_fit(cols_i, rows_i) unless dims

              fit_dimensions(cols_i, rows_i, dims[:width], dims[:height])
            rescue Shoko::Error
              default_fit(cols_i, rows_i)
            end

            def png_dimensions(bytes)
              data = bytes.to_s.b
              return nil unless data.start_with?(PNG_SIGNATURE)
              return nil unless data.bytesize >= 24
              return nil unless data.byteslice(12, 4) == 'IHDR'

              width = data.byteslice(16, 4).unpack1('N')
              height = data.byteslice(20, 4).unpack1('N')
              return nil if width.to_i <= 0 || height.to_i <= 0

              { width: width.to_i, height: height.to_i }
            end

            def normalized_fit_limits(max_cols, max_rows)
              cols_i = max_cols.to_i
              rows_i = max_rows.to_i
              [[cols_i, 1].max, [rows_i, 1].max]
            end

            def normalized_dimensions(image_id)
              dims = @dimensions[image_id]
              return nil unless dims

              width = dims[:width].to_i
              height = dims[:height].to_i
              return nil if width <= 0 || height <= 0

              { width: width, height: height }
            end

            def fit_dimensions(cols_i, rows_i, image_width, image_height)
              aspect = image_width.to_f / image_height
              target_cols = fitted_cols_for_rows(rows_i, aspect)

              if target_cols <= cols_i
                build_fit(cols: target_cols, rows: rows_i, max_cols: cols_i)
              else
                target_rows = fitted_rows_for_cols(cols_i, rows_i, aspect)
                build_fit(cols: cols_i, rows: target_rows, max_cols: cols_i)
              end
            end

            def fitted_cols_for_rows(rows_i, aspect)
              cols = (rows_i.to_f * aspect / DEFAULT_CELL_ASPECT).floor
              cols.positive? ? cols : 1
            end

            def fitted_rows_for_cols(cols_i, max_rows, aspect)
              rows = (cols_i.to_f * DEFAULT_CELL_ASPECT / aspect).floor
              rows = 1 if rows <= 0
              [rows, max_rows].min
            end

            def build_fit(cols:, rows:, max_cols:)
              {
                cols: cols,
                rows: rows,
                col_offset: centered_col_offset(max_cols, cols),
                row_offset: 0,
              }
            end

            def centered_col_offset(max_cols, fit_cols)
              offset = ((max_cols - fit_cols) / 2.0).floor
              offset.negative? ? 0 : offset
            end

            def default_fit(cols_i, rows_i)
              { cols: cols_i, rows: rows_i, col_offset: 0, row_offset: 0 }
            end
          end
        end
      end
    end
  end
end
