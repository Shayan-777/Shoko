# frozen_string_literal: true

require_relative '../../shared/text_sanitizer'
require_relative 'in_book_search_service/search_match'
require_relative 'in_book_search_service/search_result'
require_relative 'in_book_search_service/searchable_line'

module Shoko
  module Core
    module Services
      # Searches for a query across all chapter lines in a loaded document.
      #
      # Matching always runs over the chapters' PLAIN parsed lines (one line
      # per paragraph), never over wrapped display lines: plain lines are
      # complete regardless of pagination-cache state, and a phrase that
      # straddles a wrap boundary still matches. The result navigator maps a
      # selected hit onto the current wrapped layout by its context, so
      # navigation stays precise without the scan depending on the layout.
      class InBookSearchService
        DEFAULT_MAX_RESULTS = 250
        # Enough surrounding words to fill both preview rows; the renderer trims to
        # fit, so a generous window simply gives it more to lay out.
        DEFAULT_CONTEXT_WORDS = 16

        # @param chapter_formatter [#plain_lines_for] Optional. When provided,
        #   the chapter's parsed plain lines are fetched from the formatter
        #   rather than read off `chapter.lines`. The formatter is the new
        #   owner of parsed-content publication; the chapter struct is no
        #   longer back-written.
        # @param document_provider [#call, nil] Optional late binding for the
        #   document. Opening an already-cached book builds this service
        #   before the document is loaded (the reader's startup loader
        #   publishes it afterwards), so a fixed +document+ of nil would
        #   leave every chapter scan permanently empty.
        def initialize(document:, logger: nil, chapter_formatter: nil, document_provider: nil)
          @document = document
          @document_provider = document_provider
          @logger = logger
          @chapter_formatter = chapter_formatter
        end

        def search(query, max_results: DEFAULT_MAX_RESULTS, context_words: DEFAULT_CONTEXT_WORDS)
          normalized_query = normalize_query(query)
          return empty_result(normalized_query) if normalized_query.empty?

          pattern = search_pattern(normalized_query)
          return empty_result(normalized_query) unless pattern

          max, context = normalized_search_limits(max_results, context_words)
          hits = []
          total_matches = 0

          each_chapter_line do |line|
            total_matches += collect_line_matches(hits, line, pattern, max: max, context_words: context)
          end

          SearchResult.new(query: normalized_query, matches: hits, total_matches: total_matches)
        end

        private

        def empty_result(query) = SearchResult.new(query: query.to_s, matches: [], total_matches: 0)

        def normalize_query(query) = sanitize_line(query).strip

        def search_pattern(query)
          escaped = Regexp.escape(query)
          if single_word_query?(query)
            /(?<![\p{Alnum}_])#{escaped}(?![\p{Alnum}_])/i
          else
            /#{escaped}/i
          end
        end

        def single_word_query?(query) = query.match?(/\A[\p{Alnum}_'-]+\z/)

        def each_chapter_line
          each_document_chapter do |chapter_index, chapter|
            chapter_title = chapter_title_for(chapter, chapter_index)
            chapter_lines(chapter, chapter_index).each_with_index do |line, line_index|
              next if line.empty?

              yield SearchableLine.new(
                chapter_index: chapter_index, chapter_title: chapter_title,
                line_index: line_index, text: line
              )
            end
          end
        end

        def each_document_chapter
          doc = document
          return unless doc

          chapter_count = [doc.chapter_count.to_i, 0].max
          chapter_count.times do |chapter_index|
            chapter = doc.get_chapter(chapter_index)
            next unless chapter

            yield chapter_index, chapter
          end
        end

        # The reader builds this service before a cached book's document has
        # loaded; the provider re-reads the published document so the search
        # never sticks to that early nil.
        def document
          @document ||= @document_provider&.call
        end

        # +chapter+ may be nil (defensive against stale documents), and a
        # missing chapter must fall back to the numbered label, not crash the
        # search.
        def chapter_title_for(chapter, chapter_index)
          title = chapter&.title.to_s.strip
          return title unless title.empty?

          "Chapter #{chapter_index + 1}"
        end

        # The formatter owns parsed-content publication, but importers that
        # produce plain text (PDF, Kindle, RTF) set `chapter.lines` directly
        # and the formatter has nothing for them — same fallback as
        # WrappingService#plain_lines_for_chapter, without which those books
        # are silently unsearchable in the chapter scan.
        def chapter_lines(chapter, chapter_index)
          lines = Array(@chapter_formatter&.plain_lines_for(document, chapter_index))
          lines = Array(chapter.lines) if lines.empty?

          lines.filter_map do |line|
            text = sanitize_line(extract_line_text(line))
            next if text.empty?

            text
          end
        end

        # Extract the textual content from a chapter line.
        #
        # Lines can be either plain Strings (importer output, fallback
        # paths) or display-line-shaped objects (formatter output, with a
        # `#text` method). We branch on `String` rather than referencing
        # the renderer's `DisplayLine` constant directly so core stays
        # free of presentation types. Anything else raises naturally via
        # NoMethodError on `line.text`.
        def extract_line_text(line)
          case line
          when String then line
          else line.text.to_s
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

        def normalized_search_limits(max_results, context_words)
          [[max_results.to_i, 1].max, [context_words.to_i, 1].max]
        end

        def collect_line_matches(hits, line, pattern, max:, context_words:)
          matches = 0

          find_matches(line.text, pattern) do |start_pos, end_pos|
            matches += 1
            next if hits.length >= max

            hits << build_search_match(line, start_pos, end_pos, context_words: context_words)
          end

          matches
        end

        def build_search_match(line, start_pos, end_pos, context_words:)
          before, match, after = context_slice(line.text, start_pos, end_pos, context_words: context_words)
          SearchMatch.new(
            chapter_index: line.chapter_index,
            chapter_title: line.chapter_title,
            line_index: line.line_index,
            before: before,
            match: match,
            after: after
          )
        end
      end
    end
  end
end
