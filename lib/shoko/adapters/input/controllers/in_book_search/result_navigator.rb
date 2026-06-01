# frozen_string_literal: true

require_relative '../../../../shared/text_sanitizer'
require_relative '../../../../shared/type_coercion'
require_relative '../../../../application/ports/outbound/formatting/display_line'

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          # Resolves search-result destinations and landing highlights for in-book search.
          class ResultNavigator
            LANDING_HIGHLIGHT_DURATION = 2.0
            SEARCH_CONTEXT_WINDOW = 64

            ResultOpen = Data.define(:label)

            def initialize(reader_state:, reader_session_mutator:, reader_controller:, state_controller:,
                           page_calculator:, clock:)
              @reader_state = reader_state
              @reader_session_mutator = reader_session_mutator
              @reader_controller = reader_controller
              @state_controller = state_controller
              @page_calculator = page_calculator
              @clock = clock
            end

            def clear_landing_highlight
              @reader_session_mutator&.update_reader(search_landing_highlight: nil)
            end

            def open(result_entry)
              chapter_index = integer_result_value(result_entry, :chapter_index) || 0
              line_offset = resolve_result_line_offset(result_entry, chapter_index: chapter_index)
              return nil unless jump_to_destination(chapter_index, line_offset)

              set_search_landing_highlight(result_entry, chapter_index: chapter_index, line_offset: line_offset)
              @reader_controller&.draw_screen
              ResultOpen.new(label: chapter_label(result_entry, chapter_index))
            end


            private

            def jump_to_destination(chapter_index, line_offset)
              controller = resolve_state_controller
              return nil unless controller

              controller.jump_to_chapter_offset(chapter_index, line_offset)
              controller
            end

            def resolve_state_controller
              return @state_controller if @state_controller
              return nil unless @reader_controller

              @reader_controller.state_controller
            end

            def integer_result_value(entry, key)
              Shoko::Shared::TypeCoercion.optional_integer(result_value(entry, key))
            end

            def extract_search_line_text(line)
              if line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)
                line.text.to_s
              else
                line.to_s
              end
            end

            def normalize_search_text(text)
              Shoko::Shared::TextSanitizer.sanitize(
                text.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).gsub(/\s+/, '').downcase
            end

            def result_value(entry, key)
              value = entry[key]
              value = entry[key.to_s] if value.nil?
              value.to_s
            end


            def set_search_landing_highlight(result_entry, chapter_index:, line_offset:)
              payload = build_search_landing_highlight(result_entry,
                                                       chapter_index: chapter_index,
                                                       line_offset: line_offset)
              return if payload.nil?

              @reader_session_mutator&.update_reader(search_landing_highlight: payload)
            end

            def build_search_landing_highlight(result_entry, chapter_index:, line_offset:)
              entry = result_entry.is_a?(Hash) ? result_entry : {}
              match_text = result_value(entry, :match)
              return nil if match_text.empty?

              query = result_value(entry, :query)
              query = match_text if query.empty?

              {
                chapter_index: chapter_index,
                line_index: line_offset,
                page_index: current_page_index,
                expires_at: monotonic_now + LANDING_HIGHLIGHT_DURATION,
                query: query,
                before: result_value(entry, :before),
                match_text: match_text,
                after: result_value(entry, :after),
              }
            end

            def current_page_index
              @reader_state&.current_page_index
            end

            def chapter_label(result_entry, chapter_index)
              label = result_value(result_entry, :chapter_title).strip
              label.empty? ? "Chapter #{chapter_index + 1}" : label
            end

            def monotonic_now
              @clock&.monotonic_now || Process.clock_gettime(Process::CLOCK_MONOTONIC)
            rescue Shoko::Error, SystemCallError
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end


            def resolve_result_line_offset(result_entry, chapter_index:)
              fallback = integer_result_value(result_entry, :line_index) || 0
              direct_wrapped = direct_wrapped_result_line_offset(result_entry,
                                                                 chapter_index: chapter_index,
                                                                 fallback: fallback)
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


            def locate_wrapped_line_offset(chapter_index_data, result_entry)
              search_text = chapter_index_data[:text]
              spans = chapter_index_data[:spans]
              context = wrapped_search_context(result_entry)
              return nil unless searchable_wrapped_context?(search_text, context)

              match = locate_wrapped_search_match(search_text, wrapped_search_targets(context), context)
              return nil unless match

              line_offset_for_char_index(spans, match[:match_start])
            end

            def wrapped_search_context(result_entry)
              {
                before_text: normalize_search_text(result_value(result_entry, :before)),
                match_text: normalize_search_text(result_value(result_entry, :match)),
                after_text: normalize_search_text(result_value(result_entry, :after)),
                query_text: normalize_search_text(result_value(result_entry, :query)),
              }
            end

            def searchable_wrapped_context?(search_text, context)
              !search_text.to_s.empty? && !context[:match_text].empty?
            end

            def wrapped_search_targets(context)
              targets = []
              wrapped_search_target_definitions(context).each do |definition|
                append_wrapped_search_target(targets, **definition)
              end
              targets
            end

            def wrapped_search_target_definitions(context)
              targets = base_wrapped_search_targets(context)
              append_wrapped_context_targets(targets, context)
              append_wrapped_query_target(targets, context)
              targets
            end

            def base_wrapped_search_targets(context)
              [
                {
                  text: "#{context[:before_text]}#{context[:match_text]}#{context[:after_text]}",
                  match_offset: context[:before_text].length,
                  base: 40,
                },
                {
                  text: context[:match_text],
                  match_offset: 0,
                  base: 20,
                },
              ]
            end

            def append_wrapped_context_targets(targets, context)
              append_wrapped_context_target(targets, context[:before_text], context[:match_text], 32)
              append_wrapped_context_target(targets, context[:after_text], context[:match_text], 32, trailing: true)
            end

            def append_wrapped_context_target(targets, context_text, match_text, base, trailing: false)
              return if context_text.empty?

              text = trailing ? "#{match_text}#{context_text}" : "#{context_text}#{match_text}"
              match_offset = trailing ? 0 : context_text.length
              targets << { text: text, match_offset: match_offset, base: base }
            end

            def append_wrapped_query_target(targets, context)
              query_text = context[:query_text]
              return if query_text.empty? || query_text == context[:match_text]

              targets << { text: query_text, match_offset: 0, base: 16 }
            end

            def append_wrapped_search_target(targets, text:, match_offset:, base:)
              return if text.empty?

              key = [text, match_offset]
              return if targets.any? { |candidate| key == [candidate[:text], candidate[:match_offset]] }

              targets << { text: text, match_offset: match_offset, base: base }
            end

            def locate_wrapped_search_match(text, targets, context)
              wrapped_search_matches(text, targets, context)
                .max_by { |match| [match[:score], -match[:match_start]] }
            end

            def wrapped_search_matches(text, targets, context)
              Array(targets).flat_map do |target|
                wrapped_search_occurrences(text, target[:text]).map do |occurrence|
                  build_wrapped_search_match(text, occurrence, target, context)
                end
              end
            end

            def build_wrapped_search_match(text, occurrence, target, context)
              match_start = occurrence[:start] + target[:match_offset]
              {
                score: wrapped_search_match_score(text, match_start, context, target[:base]),
                match_start: match_start,
              }
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

            def wrapped_search_match_score(text, match_start, context, base_score)
              match_end = match_start + context[:match_text].length
              base_score.to_i +
                wrapped_search_exact_context_score(text, match_start, match_end, context) +
                wrapped_search_window_score(text, match_start, match_end, context)
            end

            def wrapped_search_exact_context_score(text, match_start, match_end, context)
              score = 0
              score += 8 if wrapped_search_prefix_match?(text, match_start, context[:before_text])
              score += 8 if wrapped_search_suffix_match?(text, match_end, context[:after_text])
              score
            end

            def wrapped_search_window_score(text, match_start, match_end, context)
              window = wrapped_search_window(text, match_start, match_end)
              score = 0
              score += 2 if wrapped_search_window_include?(window, context[:before_text])
              score += 2 if wrapped_search_window_include?(window, context[:after_text])
              score
            end

            def wrapped_search_prefix_match?(text, match_start, before_text)
              return false if before_text.empty?

              text[[match_start - before_text.length, 0].max...match_start].to_s == before_text
            end

            def wrapped_search_suffix_match?(text, match_end, after_text)
              return false if after_text.empty?

              text[match_end, after_text.length].to_s == after_text
            end

            def wrapped_search_window(text, match_start, match_end)
              window_start = [match_start - SEARCH_CONTEXT_WINDOW, 0].max
              window_end = [match_end + SEARCH_CONTEXT_WINDOW, text.length].min
              text[window_start...window_end].to_s
            end

            def wrapped_search_window_include?(window, candidate)
              !candidate.empty? && window.include?(candidate)
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
