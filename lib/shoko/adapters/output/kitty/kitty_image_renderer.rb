# frozen_string_literal: true

require 'digest/sha1'

require_relative 'resource_loader'
require_relative 'image_transcoder'
require_relative 'kitty_graphics'
require_relative 'kitty_image_renderer/geometry_support'
require_relative 'kitty_image_renderer/transmission_support'
require_relative 'kitty_image_renderer/placement_support'

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
          include GeometrySupport
          include TransmissionSupport
          include PlacementSupport

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
        end
      end
    end
  end
end
