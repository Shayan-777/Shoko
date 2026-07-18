# frozen_string_literal: true

require_relative '../ports/internal/reader_document'

module Shoko
  module Application
    module Models
      # Application read model for a loaded book.
      #
      # The model trusts the importer (the only layer that legitimately
      # knows the source path) to have produced a non-empty title — every
      # importer uses `metadata[:title] || fallback_title(source_path)` so
      # `book.title` is always populated. If a title is still missing here,
      # the importer failed its contract and we treat it as a parse error.
      class ReaderDocument
        include Shoko::Application::Ports::Internal::ReaderDocument

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

        private

        def assign_book_payload(book)
          @title = ensure_title!(book&.title)
          @language = book&.language || 'en_US'
          @metadata = book&.metadata || {}
          @chapters = Array(book&.chapters).dup
          @toc_entries = Array(book&.toc_entries).dup
          @resources = (book&.resources || {}).dup
        end

        def ensure_title!(title)
          str = title.to_s.strip
          return title unless str.empty?

          raise Shoko::BookParseError.new(
            'importer produced no title; importers must provide metadata[:title] or a fallback',
            @source_path
          )
        end

        def ensure_chapters_exist
          return unless @chapters.empty?

          raise Shoko::BookParseError.new('book contains no chapters', @source_path)
        end
      end
    end
  end
end
