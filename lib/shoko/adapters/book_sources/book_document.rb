# frozen_string_literal: true

require_relative '../../core/book_formats/epub/html_processor'
require_relative '../../shared/text_sanitizer'
require_relative '../../core/models/chapter'
require_relative '../../core/models/toc_entry'

module Shoko
  module Adapters::BookSources
    # Represents an ebook document backed by the cache pipeline.
    # The document always operates on in-memory chapter objects; no temporary
    # extraction to disk is required.  Supports any format registered with
    # {FormatRegistry}.
    class BookDocument
      attr_reader :title, :chapters, :language, :source_path,
                  :cache_path, :cache_sha, :toc_entries, :metadata, :resources

      # @param path [String] Path to EPUB file
      # @param formatting_service [Object, nil] Formatting service
      # @param background_worker [Object, nil] Background worker
      # @param progress_reporter [Object, nil] Progress reporter
      # @param logger [Core::Ports::Outbound::Logging] Logger adapter (required)
      # @param instrumentation [Core::Ports::Outbound::Instrumentation, nil] Instrumentation service
      def initialize(path, logger:, formatting_service: nil, background_worker: nil, progress_reporter: nil,
                     instrumentation: nil, runtime_config: nil, book_cache: nil)
        @open_path = File.expand_path(path)
        @formatting_service = formatting_service
        @background_worker = background_worker
        @progress_reporter = progress_reporter
        @logger = logger
        @instrumentation = instrumentation
        @runtime_config = runtime_config
        @book_cache = book_cache

        @title = fallback_title(@open_path)
        @language = 'en_US'
        @chapters = []
        @toc_entries = []
        @metadata = {}
        @resources = {}
        @cache_path = nil
        @source_path = @open_path
        @loaded_from_cache = false

        load_via_pipeline!
      rescue Shoko::Error => e
        create_error_chapter(e)
      rescue StandardError => e
        @logger.error('BookDocument initialization failed', path: @open_path, error: e.message)
        create_error_chapter(e)
      end

      def chapter_count
        @chapters.size
      end

      def get_chapter(index)
        return nil unless index.is_a?(Integer) && index >= 0 && index < @chapters.length

        chapter = @chapters[index]
        return nil unless chapter

        ensure_formatted_chapter(chapter, index)
        chapter.lines = fallback_plain_lines(chapter.raw_content) if chapter.lines.nil? || chapter.lines.empty?
        chapter
      end

      def cached?
        @loaded_from_cache
      end

      def canonical_path
        @source_path || @open_path
      end

      # Backwards compatibility for components that previously expected a cache
      # directory. Returns the directory containing the `.cache` file.
      def cache_dir
        return nil unless @cache_path

        File.dirname(@cache_path)
      end

      private

      def load_via_pipeline!
        result = instrument('import.pipeline') do
          instrument('cache.pipeline') do
            pipeline = @book_cache || Adapters::Storage::BookCachePipeline.new(
              progress_reporter: @progress_reporter,
              runtime_config: @runtime_config
            )
            pipeline.load(@open_path, formatting_service: @formatting_service)
          end
        end

        apply_pipeline_result(result)
      end

      def apply_pipeline_result(result)
        book = result.book
        @instrumentation&.annotate(
          cache_hit: result.loaded_from_cache,
          chapters: Array(book&.chapters).size,
          book: result.source_path || @open_path
        )
        @cache_path = result.cache_path
        @cache_sha = derive_cache_sha(@cache_path)
        @source_path = result.source_path || @open_path
        @loaded_from_cache = result.loaded_from_cache

        @title = present_or_fallback(book.title, fallback_title(@source_path))
        @language = book.language || @language
        @metadata = book.metadata || {}
        @chapters = Array(book.chapters).dup
        @toc_entries = Array(book.toc_entries).dup
        @resources = (book.resources || {}).dup

        ensure_chapters_exist
      end

      def derive_cache_sha(path)
        return nil unless path && !path.to_s.empty?

        File.basename(path.to_s, File.extname(path.to_s))
      rescue StandardError
        nil
      end

      def present_or_fallback(value, fallback)
        str = value.to_s.strip
        str.empty? ? fallback : value
      end

      def ensure_chapters_exist
        return unless @chapters.empty?

        @chapters << Core::Models::Chapter.new(
          number: '1',
          title: 'Empty Book',
          lines: ['This book appears to be empty.'],
          metadata: nil,
          blocks: nil,
          raw_content: nil
        )
        @toc_entries = []
      end

      def create_error_chapter(error)
        @chapters = [
          Core::Models::Chapter.new(
            number: '1',
            title: 'Error Loading',
            lines: ["Error: #{error.message}"],
            metadata: nil,
            blocks: nil,
            raw_content: nil
          ),
        ]
        @toc_entries = []
      end

      def ensure_formatted_chapter(chapter, index)
        return unless @formatting_service && chapter

        chapter_index = index.to_i
        return if chapter.blocks && !chapter.blocks.empty?

        # Always format synchronously so rendering/pagination receives structured lines immediately.
        format_chapter_sync(chapter_index, chapter, raise_on_error: true)
      end

      def fallback_plain_lines(content)
        return [] unless content

        text = Core::BookFormats::Epub::HTMLProcessor.html_to_text(content.to_s)
        text.split("\n").map(&:rstrip)
      end

      def fallback_title(path)
        raw = File.basename(path, File.extname(path)).tr('_', ' ')
        Shoko::Shared::TextSanitizer.sanitize(raw, preserve_newlines: false,
                                                    preserve_tabs: false)
      end

      def instrument(label, &)
        if @instrumentation
          @instrumentation.measure(label, &)
        else
          yield
        end
      end

      def format_chapter_sync(index, chapter, raise_on_error:)
        instrument('formatting.ensure') do
          @formatting_service.ensure_formatted!(self, index, chapter)
        end
      rescue Shoko::FormattingError => e
        @logger.error('Formatting error', error: e.message, chapter: index + 1)
        raise if raise_on_error
      rescue StandardError => e
        @logger.debug('Formatting service failed', error: e.message, chapter: index + 1)
        nil
      end
    end
  end
end
