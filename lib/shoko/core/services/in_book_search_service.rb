# frozen_string_literal: true

require_relative '../../shared/text_sanitizer'
require_relative '../ports/outbound/reader_document'
require_relative '../ports/outbound/reader_chapter'
require_relative '../models/content_block'

module Shoko
  module Core
    module Services
      # Searches for a query across all chapter lines in a loaded document.
      class InBookSearchService
        # Single search hit with chapter location and context around the match.
        SearchMatch = Struct.new(
          :chapter_index,
          :chapter_title,
          :line_index,
          :before,
          :match,
          :after
        )

        # Search output payload.
        SearchResult = Struct.new(
          :query,
          :matches,
          :total_matches
        )

        DEFAULT_MAX_RESULTS = 250
        DEFAULT_CONTEXT_WORDS = 4

        def initialize(document:, logger: nil)
          unless document.nil? || document.is_a?(Shoko::Core::Ports::Outbound::ReaderDocument)
            raise ArgumentError, 'document must implement Core::Ports::Outbound::ReaderDocument'
          end

          @document = document
          @logger = logger
        end

        def search(query, max_results: DEFAULT_MAX_RESULTS, context_words: DEFAULT_CONTEXT_WORDS)
          normalized_query = normalize_query(query)
          return empty_result(normalized_query) if normalized_query.empty?

          pattern = search_pattern(normalized_query)
          return empty_result(normalized_query) unless pattern

          hits = []
          total_matches = 0
          max = [max_results.to_i, 1].max
          context = [context_words.to_i, 1].max

          each_chapter_line do |chapter_index, chapter_title, line_index, line|
            find_matches(line, pattern) do |start_pos, end_pos|
              total_matches += 1
              next if hits.length >= max

              before, match, after = context_slice(line, start_pos, end_pos, context_words: context)
              hits << SearchMatch.new(
                chapter_index: chapter_index,
                chapter_title: chapter_title,
                line_index: line_index,
                before: before,
                match: match,
                after: after
              )
            end
          end

          SearchResult.new(query: normalized_query, matches: hits, total_matches: total_matches)
        end

        private

        def empty_result(query)
          SearchResult.new(query: query.to_s, matches: [], total_matches: 0)
        end

        def normalize_query(query)
          sanitize_line(query).strip
        end

        def search_pattern(query)
          escaped = Regexp.escape(query)
          if single_word_query?(query)
            /(?<![\p{Alnum}_])#{escaped}(?![\p{Alnum}_])/i
          else
            /#{escaped}/i
          end
        end

        def single_word_query?(query)
          query.match?(/\A[\p{Alnum}_'-]+\z/)
        end

        def each_chapter_line
          each_document_chapter do |chapter_index, chapter|
            chapter_title = chapter_title_for(chapter, chapter_index)
            chapter_lines(chapter).each_with_index do |line, line_index|
              next if line.empty?

              yield chapter_index, chapter_title, line_index, line
            end
          end
        end

        def each_document_chapter
          return unless @document

          chapter_count = [@document.chapter_count.to_i, 0].max
          chapter_count.times do |chapter_index|
            chapter = @document.get_chapter(chapter_index)
            next unless chapter

            unless chapter.is_a?(Shoko::Core::Ports::Outbound::ReaderChapter)
              raise ArgumentError, 'chapter must implement Core::Ports::Outbound::ReaderChapter'
            end

            yield chapter_index, chapter
          end
        end

        def chapter_title_for(chapter, chapter_index)
          title = chapter.title.to_s.strip
          return title unless title.empty?

          "Chapter #{chapter_index + 1}"
        end

        def chapter_lines(chapter)
          lines = Array(chapter.lines)

          lines.filter_map do |line|
            text = sanitize_line(extract_line_text(line))
            next if text.empty?

            text
          end
        end

        def extract_line_text(line)
          if line.is_a?(Shoko::Core::Models::DisplayLine)
            line.text.to_s
          elsif line.is_a?(String)
            line
          else
            raise ArgumentError, "unsupported chapter line type: #{line.class}"
          end
        end

        def sanitize_line(text)
          Shoko::Shared::TextSanitizer.sanitize(
            text.to_s,
            preserve_newlines: false,
            preserve_tabs: false
          ).gsub(/\s+/, ' ').strip
        end

        def find_matches(line, pattern)
          offset = 0
          while (match = pattern.match(line, offset))
            start_pos = match.begin(0)
            end_pos = match.end(0)
            yield start_pos, end_pos
            offset = start_pos + [match[0].length, 1].max
          end
        end

        def context_slice(line, start_pos, end_pos, context_words:)
          before_text = line[0...start_pos].to_s
          match_text = line[start_pos...end_pos].to_s
          after_text = line[end_pos..].to_s

          before_words = before_text.split(/\s+/).reject(&:empty?).last(context_words).to_a
          after_words = after_text.split(/\s+/).reject(&:empty?).first(context_words).to_a

          before = before_words.empty? ? '' : "#{before_words.join(' ')} "
          after = after_words.empty? ? '' : " #{after_words.join(' ')}"

          [before, match_text, after]
        end
      end
    end
  end
end
