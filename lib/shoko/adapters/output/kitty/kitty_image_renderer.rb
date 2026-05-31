# frozen_string_literal: true

require 'digest/sha1'

require_relative 'resource_loader'
require_relative 'image_transcoder'
require_relative 'kitty_graphics'

module Shoko
  module Adapters
    module Output
      module Kitty
        # Stateful renderer that transmits images once per session and then places
        # them on screen using the Kitty graphics protocol.
        class KittyImageRenderer
          MAX_ID = 4_294_967_295
          PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
          DEFAULT_CELL_ASPECT = 0.5 # width/height ratio for typical terminal cells
          RENDERABLE_SOURCE_EXTENSIONS = %w[.png .jpg .jpeg].freeze

          def initialize(resource_loader: ResourceLoader.new,
                         transcoder: ImageTranscoder.new)
            @resource_loader = resource_loader
            @transcoder = transcoder
            @transmitted = {}
            @dimensions = {}
            @virtual_placements = {}
          end

          def enabled?(config_store)
            KittyGraphics.enabled_for?(config_store)
          end

          def reset_virtual_placements!
            @virtual_placements.clear
          end

          def render(output:, book_sha:, epub_path:, chapter_entry_path:, src:, row:, col:, cols:, rows:,
                     placement_id:, **options)
            request = render_request(
              output:, book_sha:, epub_path:, chapter_entry_path:, src:, row:, col:, cols:, rows:,
              placement_id:, depth: options.fetch(:z, nil)
            )
            return nil unless request
            return nil unless transmit_image(request)

            place_rendered_image(request)
          end

          def renderable_source?(src)
            source = core_src(src)
            return false if source.nil? || source.empty?

            ext = File.extname(source).downcase
            RENDERABLE_SOURCE_EXTENSIONS.include?(ext)
          end

          def warm_cache(book_sha:, epub_path:, chapter_entry_path:, src:)
            return false unless epub_path && File.file?(epub_path)

            entry_path = resolved_entry_path(chapter_entry_path, src)
            return false unless entry_path

            return false unless renderable_source?(entry_path)

            request = warm_cache_request(book_sha, epub_path, entry_path)
            return :cached if cached_png_entry?(request)

            png_bytes = build_png_cache(request)
            return false unless png_bytes

            cache_image_dimensions(request, png_bytes)
            :warmed
          end

          def prepare_virtual(
            output:,
            book_sha:,
            epub_path:,
            chapter_entry_path:,
            src:,
            cols:,
            rows:,
            placement_id: nil,
            **options
          )
            request = resolved_image_request(
              output: output,
              book_sha: book_sha,
              epub_path: epub_path,
              chapter_entry_path: chapter_entry_path,
              src: src,
              cols: cols,
              rows: rows,
              placement_id: placement_id,
              depth: options.fetch(:z, nil)
            )
            return nil unless request
            return nil unless transmit_image(request)
            return nil unless ensure_virtual_placement(request)

            request[:image_id]
          end

          private

          def warm_cache_request(book_sha, epub_path, entry_path)
            {
              book_sha: book_sha,
              epub_path: epub_path,
              entry_path: entry_path,
              image_id: image_id_for(book_sha, epub_path, entry_path),
            }
          end

          def cached_png_entry?(request)
            @resource_loader.cached?(book_sha: request[:book_sha], entry_path: png_cache_key(request[:entry_path]))
          end

          def png_cache_key(entry_path)
            "#{entry_path}|kitty_png_v1"
          rescue Shoko::Error
            "#{entry_path}|kitty_png_v1"
          end

          def core_src(src)
            src.to_s.split(/[?#]/, 2).first.to_s
          rescue Shoko::Error
            src.to_s
          end

          def image_id_for(book_sha, epub_path, entry_path)
            seed = "#{book_sha}|#{epub_path}|#{entry_path}"
            hashed_id(seed)
          end

          def hashed_id(seed)
            raw = Digest::SHA1.digest(seed.to_s)
            int = raw.unpack1('N') & 0xFF_FF_FF
            int.zero? ? 1 : int
          end

          def resolved_image_request(output:, book_sha:, epub_path:, chapter_entry_path:, src:, cols:, rows:,
                                     placement_id:, depth:, row: nil, col: nil)
            return nil unless valid_render_target?(output, epub_path)

            entry_path = resolved_entry_path(chapter_entry_path, src)
            return nil unless entry_path

            request_attributes_for_entry(
              entry_path,
              output:, book_sha:, epub_path:, chapter_entry_path:, src:, row:, col:, cols:, rows:,
              placement_id:, depth:
            )
          end

          def resolved_entry_path(chapter_entry_path, src)
            @resource_loader.resolve_chapter_relative(chapter_entry_path, src)
          end

          def valid_render_target?(output, epub_path)
            output && epub_path && File.file?(epub_path)
          end

          def request_attributes(output:, book_sha:, epub_path:, chapter_entry_path:, entry_path:, src:, row:, col:,
                                 cols:, rows:, placement_id:, depth:)
            {
              output: output,
              book_sha: book_sha,
              epub_path: epub_path,
              chapter_entry_path: chapter_entry_path,
              entry_path: entry_path,
              src: src,
              row: row,
              col: col,
              cols: cols.to_i,
              rows: rows.to_i,
              placement_id: placement_id,
              z: depth,
              image_id: image_id_for(book_sha, epub_path, entry_path),
            }
          end

          def render_request(output:, book_sha:, epub_path:, chapter_entry_path:, src:, row:, col:, cols:, rows:,
                             placement_id:, depth:)
            resolved_image_request(output:, book_sha:, epub_path:, chapter_entry_path:, src:, cols:, rows:,
                                   placement_id:, depth:, row:, col:)
          end

          def request_attributes_for_entry(entry_path, **attributes)
            request_attributes(**attributes, entry_path: entry_path)
          end

          # Image-dimension probing and terminal-cell geometry fitting.
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

          # Screen placement and virtual-placement registry behavior.
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

          # PNG cache loading, transmission, and dimension caching.
          def transmit_image(request)
            image_id = request[:image_id]
            return image_id if @transmitted[image_id]

            png_bytes = load_png_bytes(request)
            return nil unless png_bytes

            cache_image_dimensions(request, png_bytes)
            KittyGraphics.transmit_png(image_id, png_bytes, quiet: true).each do |sequence|
              emit_raw(request[:output], sequence)
            end

            @transmitted[image_id] = true
            image_id
          end

          def load_png_bytes(request)
            cache_key = png_cache_key(request[:entry_path])
            if @resource_loader.cached?(book_sha: request[:book_sha], entry_path: cache_key)
              return @resource_loader.fetch(
                book_sha: request[:book_sha],
                epub_path: request[:epub_path],
                entry_path: request[:entry_path],
                cache_key: cache_key,
                persist: false
              )
            end

            build_png_cache(request)
          end

          def build_png_cache(request)
            source_bytes = @resource_loader.fetch(
              book_sha: request[:book_sha],
              epub_path: request[:epub_path],
              entry_path: request[:entry_path],
              persist: true
            )
            png_bytes = @transcoder.to_png(source_bytes)
            return nil unless png_bytes

            @resource_loader.cache_entry(
              book_sha: request[:book_sha],
              entry_path: png_cache_key(request[:entry_path]),
              bytes: png_bytes
            )
            png_bytes
          end

          def cache_image_dimensions(request, png_bytes)
            dims = png_dimensions(png_bytes)
            @dimensions[request[:image_id]] = dims if dims
          end
        end
      end
    end
  end
end
