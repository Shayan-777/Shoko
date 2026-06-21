# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Kitty
        # Loader contract used by Kitty image rendering.
        #
        # Resource bytes come from a zip (EPUB) by default, but Kindle/KF8
        # containers aren't zips — their images live in the PDB image records.
        # When the source is a Kindle file and a +kindle_image_source+ is wired,
        # fetch reads from there and persists through the same blob cache, so the
        # caching, transcoding, and render path downstream are entirely shared.
        class ResourceLoader
          KINDLE_EXTENSIONS = %w[.mobi .azw .azw3].freeze

          def initialize(loader:, kindle_image_source: nil)
            @loader = loader
            @kindle_image_source = kindle_image_source
          end

          def resolve_chapter_relative(chapter_entry_path, src)
            @loader.class.resolve_chapter_relative(chapter_entry_path, src)
          end

          def fetch(book_sha:, epub_path:, entry_path:, persist:, cache_key: nil)
            args = { book_sha: book_sha, epub_path: epub_path, entry_path: entry_path,
                     cache_key: cache_key, persist: persist }
            return fetch_kindle_image(**args) if kindle_source?(epub_path)

            @loader.fetch(**args)
          end

          def cache_entry(book_sha:, entry_path:, bytes:)
            @loader.cache_entry(book_sha: book_sha, entry_path: entry_path, bytes: bytes)
          end

          def cached?(book_sha:, entry_path:)
            @loader.cached?(book_sha: book_sha, entry_path: entry_path)
          end

          private

          def kindle_source?(epub_path)
            return false unless @kindle_image_source

            KINDLE_EXTENSIONS.include?(File.extname(epub_path.to_s).downcase)
          end

          # +entry_path+ identifies the source image to extract from the
          # container; +cache_key+ (when given — e.g. the transcoded-PNG key) is
          # where bytes are cached and looked up. Mirroring EpubResourceLoader's
          # cache_key handling is what makes the PNG cache round-trip: without
          # it, a transcoded-PNG lookup wrongly returned the raw source bytes,
          # so the terminal received a JPEG where it expected a PNG and drew
          # nothing.
          def fetch_kindle_image(book_sha:, epub_path:, entry_path:, cache_key:, persist:)
            key = cache_key.to_s.empty? ? entry_path : cache_key
            if @loader.cached?(book_sha: book_sha, entry_path: key)
              return @loader.fetch(book_sha: book_sha, epub_path: nil, entry_path: key, persist: false)
            end

            bytes = @kindle_image_source.fetch(epub_path, entry_path)
            return nil unless bytes

            @loader.cache_entry(book_sha: book_sha, entry_path: key, bytes: bytes) if persist
            bytes
          end
        end
      end
    end
  end
end
