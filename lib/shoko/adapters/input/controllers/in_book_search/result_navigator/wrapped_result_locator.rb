# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          class ResultNavigator
            module WrappedResultLocator
              private

              def resolve_result_line_offset(result_entry, chapter_index:)
                fallback = integer_result_value(result_entry, :line_index) || 0
                direct_wrapped = direct_wrapped_result_line_offset(result_entry, chapter_index: chapter_index, fallback: fallback)
                return direct_wrapped unless direct_wrapped.nil?
                return fallback unless @page_calculator

                chapter_index_data = chapter_wrapped_search_index(@page_calculator, chapter_index)
                return fallback unless chapter_index_data

                locate_wrapped_line_offset(chapter_index_data, result_entry) || fallback
              end

              def direct_wrapped_result_line_offset(result_entry, chapter_index:, fallback:)
                return nil unless wrapped_search_result?(result_entry)
                return nil unless @page_calculator

                page_hint = integer_result_value(result_entry, :page_index)
                hinted_page = resolve_result_page(@page_calculator, page_hint)
                return fallback if valid_result_page?(hinted_page, chapter_index: chapter_index, line_offset: fallback)

                chapter_pages = Array(@page_calculator.pages_data).select do |page|
                  result_page_chapter_index(page) == chapter_index.to_i
                end
                return fallback if chapter_pages.any? { |page| page_contains_line_offset?(page, fallback) }

                nil
              end

              def chapter_wrapped_search_index(page_calculator, chapter_index)
                pages = Array(page_calculator.pages_data).each_with_index.filter_map do |page, index|
                  next unless page && page[:chapter_index].to_i == chapter_index.to_i

                  page_calculator.get_page(index) || page
                end
                return nil if pages.empty?

                build_wrapped_search_index(pages.sort_by { |page| page[:start_line].to_i })
              end

              def build_wrapped_search_index(pages)
                text = +''
                spans = []

                pages.each do |page|
                  start_line = page[:start_line].to_i
                  Array(page[:lines]).each_with_index do |line, line_index|
                    normalized = normalize_search_text(extract_search_line_text(line))
                    next if normalized.empty?

                    span_start = text.length
                    text << normalized
                    spans << {
                      start: span_start,
                      finish: text.length,
                      line_offset: start_line + line_index,
                    }
                  end
                end

                return nil if text.empty? || spans.empty?

                { text: text, spans: spans }
              end

              def locate_wrapped_line_offset(chapter_index_data, result_entry)
                search_text = chapter_index_data[:text]
                spans = chapter_index_data[:spans]
                match_text = normalize_search_text(result_value(result_entry, :match))
                return nil if search_text.to_s.empty? || match_text.empty?

                before_text = normalize_search_text(result_value(result_entry, :before))
                after_text = normalize_search_text(result_value(result_entry, :after))
                targets = wrapped_search_targets(result_entry, before_text, match_text, after_text)
                match = locate_wrapped_search_match(search_text, targets, before_text, match_text, after_text)
                return nil unless match

                line_offset_for_char_index(spans, match[:match_start])
              end

              def wrapped_search_targets(result_entry, before_text, match_text, after_text)
                query_text = normalize_search_text(result_value(result_entry, :query))
                candidates = []
                candidates << { text: "#{before_text}#{match_text}#{after_text}", match_offset: before_text.length, base: 40 }
                candidates << { text: "#{before_text}#{match_text}", match_offset: before_text.length, base: 32 } unless before_text.empty?
                candidates << { text: "#{match_text}#{after_text}", match_offset: 0, base: 32 } unless after_text.empty?
                candidates << { text: match_text, match_offset: 0, base: 20 }
                candidates << { text: query_text, match_offset: 0, base: 16 } unless query_text.empty? || query_text == match_text
                candidates.reject { |candidate| candidate[:text].empty? }
                          .uniq { |candidate| [candidate[:text], candidate[:match_offset]] }
              end

              def locate_wrapped_search_match(text, targets, before_text, match_text, after_text)
                targets.each_with_object([]) do |target, matches|
                  wrapped_search_occurrences(text, target[:text]).each do |occurrence|
                    match_start = occurrence[:start] + target[:match_offset]
                    matches << {
                      score: wrapped_search_match_score(
                        text,
                        before_text: before_text,
                        match_start: match_start,
                        match_text: match_text,
                        after_text: after_text,
                        base_score: target[:base]
                      ),
                      match_start: match_start,
                    }
                  end
                end.max_by { |match| [match[:score], -match[:match_start]] }
              end

              def wrapped_search_occurrences(text, needle)
                return [] if text.to_s.empty? || needle.to_s.empty?

                matches = []
                offset = 0
                while (index = text.index(needle, offset))
                  matches << { start: index, finish: index + needle.length }
                  offset = index + [needle.length, 1].max
                end
                matches
              end

              def wrapped_search_match_score(text, before_text:, match_start:, match_text:, after_text:, base_score:)
                match_end = match_start + match_text.length
                score = base_score.to_i
                score += 8 if !before_text.empty? && text[[match_start - before_text.length, 0].max...match_start].to_s == before_text
                score += 8 if !after_text.empty? && text[match_end, after_text.length].to_s == after_text

                window_start = [match_start - SEARCH_CONTEXT_WINDOW, 0].max
                window_end = [match_end + SEARCH_CONTEXT_WINDOW, text.length].min
                window = text[window_start...window_end].to_s
                score += 2 if !before_text.empty? && window.include?(before_text)
                score += 2 if !after_text.empty? && window.include?(after_text)
                score
              end

              def line_offset_for_char_index(spans, char_index)
                span = spans.find { |entry| char_index >= entry[:start] && char_index < entry[:finish] }
                span && span[:line_offset]
              end

              def resolve_result_page(page_calculator, page_index)
                return nil unless page_index

                page_calculator.get_page(page_index)
              end

              def valid_result_page?(page, chapter_index:, line_offset:)
                page &&
                  result_page_chapter_index(page) == chapter_index.to_i &&
                  page_contains_line_offset?(page, line_offset)
              end

              def result_page_chapter_index(page)
                return nil unless page.is_a?(Hash)

                value = page[:chapter_index]
                value = page['chapter_index'] if value.nil?
                value.to_i
              end

              def page_contains_line_offset?(page, line_offset)
                return false unless page.is_a?(Hash)

                start_line = page[:start_line]
                start_line = page['start_line'] if start_line.nil?
                end_line = page[:end_line]
                end_line = page['end_line'] if end_line.nil?
                return false if start_line.nil? || end_line.nil?

                line_offset.to_i.between?(start_line.to_i, end_line.to_i)
              end

              def wrapped_search_result?(result_entry)
                result_value(result_entry, :line_space).casecmp('wrapped').zero?
              end
            end
          end
        end
      end
    end
  end
end
