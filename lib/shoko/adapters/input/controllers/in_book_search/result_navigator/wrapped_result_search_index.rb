# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          class ResultNavigator
            # Builds searchable text and span indexes for wrapped in-book search results.
            module WrappedResultSearchIndex
              private

              def chapter_wrapped_search_index(page_calculator, chapter_index)
                pages = chapter_pages_for_wrapped_search(page_calculator, chapter_index)
                return nil if pages.empty?

                build_wrapped_search_index(pages)
              end

              def chapter_pages_for_wrapped_search(page_calculator, chapter_index)
                pages = Array(page_calculator.pages_data).each_with_index.filter_map do |page, index|
                  next unless page && result_page_chapter_index(page) == chapter_index.to_i

                  page_calculator.get_page(index) || page
                end
                pages.sort_by { |page| result_page_start_line(page) }
              end

              def build_wrapped_search_index(pages)
                text = +''
                spans = []

                Array(pages).each { |page| append_wrapped_page_to_index(text, spans, page) }
                return nil if text.empty? || spans.empty?

                { text: text, spans: spans }
              end

              def append_wrapped_page_to_index(text, spans, page)
                start_line = result_page_start_line(page)
                Array(page[:lines]).each_with_index do |line, line_index|
                  append_wrapped_line_to_index(text, spans, line, start_line + line_index)
                end
              end

              def append_wrapped_line_to_index(text, spans, line, line_offset)
                normalized = normalize_search_text(extract_search_line_text(line))
                return if normalized.empty?

                span_start = text.length
                text << normalized
                spans << { start: span_start, finish: text.length, line_offset: line_offset }
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

                start_line = result_page_start_line(page)
                end_line = result_page_end_line(page)
                return false if start_line.nil? || end_line.nil?

                line_offset.to_i.between?(start_line.to_i, end_line.to_i)
              end

              def result_page_start_line(page)
                return nil unless page.is_a?(Hash)

                value = page[:start_line]
                value = page['start_line'] if value.nil?
                value.to_i
              end

              def result_page_end_line(page)
                return nil unless page.is_a?(Hash)

                value = page[:end_line]
                value = page['end_line'] if value.nil?
                value.to_i
              end
            end
          end
        end
      end
    end
  end
end
