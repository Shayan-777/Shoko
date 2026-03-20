# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Kitty
        class KittyImageRenderer
          # PNG cache loading, transmission, and dimension caching.
          module TransmissionSupport
            private

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
end
