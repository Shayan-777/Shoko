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

          def initialize(resource_loader: ResourceLoader.new,
                         transcoder: ImageTranscoder.new)
            @resource_loader = resource_loader
            @transcoder = transcoder
            @transmitted = {}
            @dimensions = {}
          end

          def enabled?(config_store)
            KittyGraphics.enabled_for?(config_store)
          end

          def render(output:, book_sha:, epub_path:, chapter_entry_path:, src:, row:, col:, cols:, rows:,
                     placement_id:, **options)
            z = options.fetch(:z, nil)
            return false unless output
            return false unless epub_path && File.file?(epub_path)

            entry_path = @resource_loader.resolve_chapter_relative(chapter_entry_path, src)
            return false unless entry_path

            image_id = image_id_for(book_sha, epub_path, entry_path)
            return false unless ensure_transmitted(output, image_id, book_sha, epub_path, entry_path)

            fit = fit_geometry(image_id, cols.to_i, rows.to_i)

            place_seq = KittyGraphics.place(image_id,
                                            placement_id: clamp_id(placement_id),
                                            cols: fit[:cols],
                                            rows: fit[:rows],
                                            quiet: true,
                                            z: z)
            abs_row = row.to_i + fit[:row_offset]
            abs_col = col.to_i + fit[:col_offset]
            emit_raw(output, TerminalOutput::ANSI.move(abs_row, abs_col) + place_seq)
            true
          end

          # Ensure the image is transmitted and has a virtual placement for Unicode placeholders.
          # Returns the image_id on success, otherwise nil.
          def prepare_virtual(output:, book_sha:, epub_path:, chapter_entry_path:, src:, cols:, rows:, placement_id: nil,
                              **options)
            z = options.fetch(:z, nil)
            return nil unless output
            return nil unless epub_path && File.file?(epub_path)

            entry_path = @resource_loader.resolve_chapter_relative(chapter_entry_path, src)
            return nil unless entry_path

            image_id = image_id_for(book_sha, epub_path, entry_path)
            return nil unless ensure_transmitted(output, image_id, book_sha, epub_path, entry_path)
            return nil unless ensure_virtual_placement(output,
                                                       image_id,
                                                       cols.to_i,
                                                       rows.to_i,
                                                       placement_id: placement_id,
                                                       z: z)

            image_id
          end

          private

          def ensure_transmitted(output, image_id, book_sha, epub_path, entry_path)
            return :cached if @transmitted[image_id]

            cache_key = png_cache_key(entry_path)
            bytes = @resource_loader.fetch(book_sha: book_sha,
                                           epub_path: epub_path,
                                           entry_path: entry_path,
                                           cache_key: cache_key,
                                           persist: false)
            png_bytes = @transcoder.to_png(bytes)
            return nil unless png_bytes

            dims = png_dimensions(png_bytes)
            @dimensions[image_id] = dims if dims

            @resource_loader.store(book_sha: book_sha, entry_path: cache_key, bytes: png_bytes)

            KittyGraphics.transmit_png(image_id, png_bytes, quiet: true).each do |seq|
              emit_raw(output, seq)
            end

            @transmitted[image_id] = true
            :transmitted
          end

          def ensure_virtual_placement(output, image_id, cols, rows, placement_id: nil, **options)
            z = options.fetch(:z, nil)
            cols_i = cols.to_i
            rows_i = rows.to_i
            return false if cols_i <= 0 || rows_i <= 0

            place_id = placement_id.to_i
            place_id = clamp_id(place_id) if place_id.positive?
            seq = KittyGraphics.virtual_place(image_id,
                                              cols: cols_i,
                                              rows: rows_i,
                                              placement_id: place_id,
                                              quiet: true,
                                              z: z)
            emit_raw(output, seq)
            true
          end

          def emit_raw(output, seq)
            output.raw(seq)
          end

          def fit_geometry(image_id, max_cols, max_rows)
            cols_i = max_cols.to_i
            rows_i = max_rows.to_i
            cols_i = 1 if cols_i <= 0
            rows_i = 1 if rows_i <= 0

            dims = @dimensions[image_id]
            return { cols: cols_i, rows: rows_i, col_offset: 0, row_offset: 0 } unless dims

            img_w = dims[:width].to_i
            img_h = dims[:height].to_i
            return { cols: cols_i, rows: rows_i, col_offset: 0, row_offset: 0 } if img_w <= 0 || img_h <= 0

            aspect = img_w.to_f / img_h
            cell_aspect = DEFAULT_CELL_ASPECT

            cols_for_rows = (rows_i.to_f * aspect / cell_aspect)
            target_cols = cols_for_rows.floor
            target_cols = 1 if target_cols <= 0

            if target_cols <= cols_i
              fit_cols = target_cols
              fit_rows = rows_i
            else
              fit_cols = cols_i
              rows_for_cols = (cols_i.to_f * cell_aspect / aspect)
              fit_rows = rows_for_cols.floor
              fit_rows = 1 if fit_rows <= 0
              fit_rows = rows_i if fit_rows > rows_i
            end

            col_offset = ((cols_i - fit_cols) / 2.0).floor
            col_offset = 0 if col_offset.negative?

            row_offset = 0

            { cols: fit_cols, rows: fit_rows, col_offset: col_offset, row_offset: row_offset }
          rescue Shoko::Error
            { cols: cols_i, rows: rows_i, col_offset: 0, row_offset: 0 }
          end

          def png_dimensions(bytes)
            data = bytes.to_s.b
            return nil unless data.start_with?(PNG_SIGNATURE)

            # PNG signature (8) + length (4) + type (4) + width (4) + height (4)
            return nil unless data.bytesize >= 24
            return nil unless data.byteslice(12, 4) == 'IHDR'

            width = data.byteslice(16, 4).unpack1('N')
            height = data.byteslice(20, 4).unpack1('N')
            return nil if width.to_i <= 0 || height.to_i <= 0

            { width: width.to_i, height: height.to_i }
          end

          def png_cache_key(entry_path)
            "#{entry_path}|kitty_png_v1"
          rescue Shoko::Error
            "#{entry_path}|kitty_png_v1"
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

          def clamp_id(value)
            int = value.to_i
            int = 1 if int <= 0
            if int > MAX_ID
              int %= MAX_ID
              int = 1 if int.zero?
            end
            int
          end
        end
      end
    end
  end
end
