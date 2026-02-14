# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Kitty
        # Loader contract used by Kitty image rendering.
        class ResourceLoader
          def initialize(loader:)
            @loader = loader
          end

          def resolve_chapter_relative(chapter_entry_path, src)
            @loader.class.resolve_chapter_relative(chapter_entry_path, src)
          end

          def fetch(book_sha:, epub_path:, entry_path:, cache_key:, persist:)
            @loader.fetch(
              book_sha: book_sha,
              epub_path: epub_path,
              entry_path: entry_path,
              cache_key: cache_key,
              persist: persist
            )
          end

          def store(book_sha:, entry_path:, bytes:)
            @loader.store(book_sha: book_sha, entry_path: entry_path, bytes: bytes)
          end
        end
      end
    end
  end
end
