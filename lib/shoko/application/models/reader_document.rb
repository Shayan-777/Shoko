# frozen_string_literal: true

require_relative '../ports/outbound/reader_document'
require_relative '../../shared/text_sanitizer'

module Shoko
  module Application
    module Models
      # Application read model for a loaded book.
      class ReaderDocument
        include Shoko::Application::Ports::Outbound::ReaderDocument

        attr_reader :title,
                    :chapters,
                    :language,
                    :source_path,
                    :cache_path,
                    :cache_sha,
                    :toc_entries,
                    :metadata,
                    :resources

        def initialize(book:, source_path:, cache_path: nil, cache_sha: nil, loaded_from_cache: false)
          @source_path = source_path
          @cache_path = cache_path
          @cache_sha = cache_sha
          @loaded_from_cache = loaded_from_cache
          assign_book_payload(book)
          ensure_chapters_exist
        end

        def chapter_count = @chapters.size

        def get_chapter(index)
          return nil unless index.is_a?(Integer) && index.between?(0, @chapters.length - 1)

          chapter = @chapters[index]
          chapter.lines ||= []
          chapter
        end

        def cached? = @loaded_from_cache

        def canonical_path = @source_path

        def cache_dir
          return nil if @cache_path.to_s.empty?

          File.dirname(@cache_path)
        end

        private

        def assign_book_payload(book)
          @title = present_or_fallback(book&.title, fallback_title(@source_path))
          @language = book&.language || 'en_US'
          @metadata = book&.metadata || {}
          @chapters = Array(book&.chapters).dup
          @toc_entries = Array(book&.toc_entries).dup
          @resources = (book&.resources || {}).dup
        end

        def ensure_chapters_exist
          return unless @chapters.empty?

          raise Shoko::BookParseError.new('book contains no chapters', @source_path)
        end

        def present_or_fallback(value, fallback)
          str = value.to_s.strip
          str.empty? ? fallback : value
        end

        def fallback_title(path)
          raw = File.basename(path.to_s, File.extname(path.to_s)).tr('_', ' ')
          Shoko::Shared::TextSanitizer.sanitize(raw, preserve_newlines: false, preserve_tabs: false)
        end
      end
    end
  end
end
