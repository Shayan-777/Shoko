# frozen_string_literal: true

require_relative '../../shared/text_sanitizer'
require_relative '../../shared/hash_normalizer'
require_relative '../../application/ports/outbound/dynamic_page_source'
require_relative 'in_book_search_service/result_types'

module Shoko
  module Core
    module Services
      # Searches for a query across all chapter lines in a loaded document.
      class InBookSearchService
        DEFAULT_MAX_RESULTS = 250
        DEFAULT_CONTEXT_WORDS = 4

        # @param page_calculator [#pages_data, #get_page, nil] Must implement the
        #   `Application::Ports::Outbound::DynamicPageSource` port when supplied —
        #   the service uses it to enumerate dynamic-mode pages for search.
        # @param chapter_formatter [#plain_lines_for] Optional. When provided,
        #   the chapter's parsed plain lines are fetched from the formatter
        #   rather than read off `chapter.lines`. The formatter is the new
        #   owner of parsed-content publication; the chapter struct is no
        #   longer back-written.
        def initialize(document:, logger: nil, page_calculator: nil, config_reader: nil, chapter_formatter: nil)
          if page_calculator && !page_calculator.is_a?(Shoko::Application::Ports::Outbound::DynamicPageSource)
            raise ArgumentError,
                  'page_calculator must implement Application::Ports::Outbound::DynamicPageSource'
          end

          @document = document
          @logger = logger
          @page_calculator = page_calculator
          @config_reader = config_reader
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

          each_searchable_line do |line|
            total_matches += collect_line_matches(hits, line, pattern, max: max, context_words: context)
          end

          SearchResult.new(query: normalized_query, matches: hits, total_matches: total_matches)
        end

        private

        def each_searchable_line(&)
          if dynamic_page_search_available?
            dynamic_line_count = each_dynamic_page_line(&)
            return dynamic_line_count unless dynamic_line_count.to_i.zero?
          end

          each_chapter_line(&)
        end

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

              yield SearchableLine.new(chapter_index, chapter_title, line_index, line, :chapter, nil)
            end
          end
        end

        def each_document_chapter
          return unless @document

          chapter_count = [@document.chapter_count.to_i, 0].max
          chapter_count.times do |chapter_index|
            chapter = @document.get_chapter(chapter_index)
            next unless chapter

            yield chapter_index, chapter
          end
        end

        def each_dynamic_page_line(&)
          pages = Array(@page_calculator&.pages_data)
          return 0 if pages.empty?

          pages.each_with_index.sum do |page, page_index|
            page ? each_searchable_dynamic_page_line(page, page_index, &) : 0
          end
        end

        def hydrate_page(page_index, fallback_page) = @page_calculator&.get_page(page_index) || fallback_page

        def normalize_page_payload(page)
          return {} unless page.is_a?(Hash)

          Shoko::Shared::HashNormalizer.deep_symbolize(page)
        end

        def dynamic_page_search_available?
          mode = @config_reader&.page_numbering_mode
          pages = Array(@page_calculator&.pages_data)
          (mode.nil? || mode == :dynamic) && !pages.empty?
        end

        def chapter_title_for(chapter, chapter_index)
          title = chapter.title.to_s.strip
          return title unless title.empty?

          "Chapter #{chapter_index + 1}"
        end

        def chapter_lines(chapter, chapter_index)
          lines = if @chapter_formatter
                    Array(@chapter_formatter.plain_lines_for(@document, chapter_index))
                  else
                    Array(chapter.lines)
                  end

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
            after: after,
            line_space: line.line_space,
            page_index: line.page_index
          )
        end

        def each_searchable_dynamic_page_line(page, page_index, &)
          page_context = hydrated_page_context(page, page_index)
          page_context[:lines].each_with_index.sum do |line, line_index|
            emit_dynamic_page_line(page_context, line, line_index, &)
          end
        end

        def hydrated_page_context(page, page_index)
          normalized_page = normalize_page_payload(page)
          chapter_index = normalized_page[:chapter_index].to_i
          chapter = @document&.get_chapter(chapter_index)
          hydrated = normalize_page_payload(hydrate_page(page_index, normalized_page))
          {
            chapter_index: chapter_index,
            chapter_title: chapter_title_for(chapter, chapter_index),
            start_line: hydrated[:start_line].to_i,
            lines: Array(hydrated[:lines]),
            page_index: page_index,
          }
        end

        def emit_dynamic_page_line(page_context, line, line_index)
          text = sanitize_line(extract_line_text(line))
          return 0 if text.empty?

          yield SearchableLine.new(
            page_context[:chapter_index],
            page_context[:chapter_title],
            page_context[:start_line] + line_index,
            text,
            :wrapped,
            page_context[:page_index]
          )
          1
        end
      end
    end
  end
end
