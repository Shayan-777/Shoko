# frozen_string_literal: true

require_relative 'support/message_notifier'
require_relative '../../../shared/text_sanitizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Handles in-book full text search popup lifecycle and input interactions.
        class InBookSearchController
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
          LANDING_HIGHLIGHT_DURATION = 2.0
          SEARCH_CONTEXT_WINDOW = 64

          def initialize(reader_state:, state_writer:, search_service:,
                         input_controller: nil, reader_controller: nil, state_controller: nil,
                         notification_service: nil, logger: nil, in_book_search_ui_session: nil,
                         clock: nil)
            @reader_state = reader_state
            @state_writer = state_writer
            @search_service = search_service
            @input_controller = input_controller
            @reader_controller = reader_controller
            @state_controller = state_controller
            @notification_service = notification_service
            @logger = logger
            @in_book_search_ui_session = in_book_search_ui_session
            @clock = clock
            raise ArgumentError, 'notification_service is required' if @notification_service.nil?
          end

          def open_in_book_search(_key = nil)
            clear_search_landing_highlight
            result = @in_book_search_ui_session.open(query: '', results: [], total_matches: 0)
            return :pass unless session_ok?(result)

            activate_search_mode
            set_message('In-book search: type query, press Enter to search', 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.open_failed', error: e.message)
            :pass
          end

          def close_in_book_search(_key = nil)
            mode = @reader_state.mode
            return :pass unless @in_book_search_ui_session.visible? || mode == :in_book_search

            result = @in_book_search_ui_session.close
            return :pass unless session_ok?(result)

            deactivate_search_mode
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.close_failed', error: e.message)
            :pass
          end

          def in_book_search_up(_key = nil)
            result = @in_book_search_ui_session.scroll_up
            session_ok?(result) ? :handled : :pass
          end

          def in_book_search_down(_key = nil)
            result = @in_book_search_ui_session.scroll_down
            session_ok?(result) ? :handled : :pass
          end

          def in_book_search_insert_char(char)
            result = session_payload(@in_book_search_ui_session.insert_char(char))
            process_in_book_search_session_result(result)
          end

          def in_book_search_backspace(_key = nil)
            result = session_payload(@in_book_search_ui_session.backspace)
            process_in_book_search_session_result(result)
          end

          def in_book_search_confirm(_key = nil)
            result = session_payload(@in_book_search_ui_session.confirm)
            process_in_book_search_session_result(result)
          end

          def in_book_search_cancel(_key = nil)
            result = session_payload(@in_book_search_ui_session.cancel)
            process_in_book_search_session_result(result)
          end

          private

          def session_payload(result)
            return result unless session_outcome?(result)

            result.payload
          end

          def session_ok?(result)
            return result.ok if session_outcome?(result)

            !!result
          end

          def session_outcome?(result)
            result.is_a?(Shoko::Shared::Contracts::SessionOutcome)
          end

          def process_in_book_search_session_result(result)
            return :pass unless result

            case result[:type]
            when :close
              close_in_book_search
            when :query_change
              :handled
            when :submit_query
              query = result[:query].to_s
              apply_search(query)
              :handled
            when :open_result
              open_result(result[:result])
            when :scroll
              :handled
            else
              :pass
            end
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.input_failed', error: e.message)
            :pass
          end

          def apply_search(query)
            result = @search_service.search(query)
            update_result = @in_book_search_ui_session.update(query: result.query,
                                                              results: result.matches,
                                                              total_matches: result.total_matches,
                                                              results_query: result.query)
            return :pass unless session_ok?(update_result)

            set_result_message(result)
            :handled
          end

          def open_result(result_entry)
            chapter_index = (result_entry[:chapter_index] || result_entry['chapter_index']).to_i
            line_offset = resolve_result_line_offset(result_entry, chapter_index: chapter_index)

            destination = jump_destination(chapter_index, line_offset)
            return :pass unless destination

            set_search_landing_highlight(result_entry, chapter_index: chapter_index, line_offset: line_offset)
            close_in_book_search
            label = result_entry[:chapter_title].to_s.strip
            label = "Chapter #{chapter_index + 1}" if label.empty?
            set_message("Opened result in #{label}", 2)
            @reader_controller&.draw_screen
            :handled
          rescue Shoko::Error => e
            @logger&.debug('in_book_search.open_result_failed', error: e.message)
            :pass
          end

          def jump_destination(chapter_index, line_offset)
            controller = resolve_state_controller
            return false unless controller

            controller.jump_to_chapter_offset(chapter_index, line_offset)
            true
          end

          def resolve_state_controller
            return @state_controller if @state_controller
            return nil unless @reader_controller

            @reader_controller.state_controller
          end

          def set_result_message(result)
            query = result.query.to_s
            return if query.empty?

            total = result.total_matches.to_i
            if total.zero?
              set_message("No matches for '#{query}'", 2)
            elsif result.matches.length < total
              set_message("#{total} matches for '#{query}' (showing first #{result.matches.length})", 2)
            else
              set_message("#{total} match#{total == 1 ? '' : 'es'} for '#{query}'", 2)
            end
          end

          def activate_search_mode
            @input_controller&.enter_modal_mode(:in_book_search)
          end

          def deactivate_search_mode
            @input_controller&.exit_modal_mode(:in_book_search)
          end

          def clear_search_landing_highlight
            @state_writer&.update_reader(search_landing_highlight: nil)
          end

          def set_search_landing_highlight(result_entry, chapter_index:, line_offset:)
            payload = build_search_landing_highlight(result_entry, chapter_index: chapter_index, line_offset: line_offset)
            return if payload.nil?

            @state_writer&.update_reader(search_landing_highlight: payload)
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

          def resolve_result_line_offset(result_entry, chapter_index:)
            fallback = (result_entry[:line_index] || result_entry['line_index']).to_i
            direct_wrapped = direct_wrapped_result_line_offset(result_entry, chapter_index: chapter_index, fallback: fallback)
            return direct_wrapped unless direct_wrapped.nil?

            page_calculator = resolve_page_calculator
            return fallback unless page_calculator&.respond_to?(:pages_data)

            chapter_index_data = chapter_wrapped_search_index(page_calculator, chapter_index)
            return fallback unless chapter_index_data

            locate_wrapped_line_offset(chapter_index_data, result_entry) || fallback
          rescue Shoko::Error
            fallback
          end

          def direct_wrapped_result_line_offset(result_entry, chapter_index:, fallback:)
            return nil unless wrapped_search_result?(result_entry)

            page_calculator = resolve_page_calculator
            return nil unless page_calculator&.respond_to?(:pages_data)

            page_hint = integer_result_value(result_entry, :page_index)
            hinted_page = resolve_result_page(page_calculator, page_hint)
            if valid_result_page?(hinted_page, chapter_index: chapter_index, line_offset: fallback)
              return fallback
            end

            chapter_pages = Array(page_calculator.pages_data).select do |page|
              result_page_chapter_index(page) == chapter_index.to_i
            end
            return fallback if chapter_pages.any? { |page| page_contains_line_offset?(page, fallback) }

            nil
          end

          def resolve_page_calculator
            return @reader_controller.page_calculator if @reader_controller&.respond_to?(:page_calculator)

            nil
          end

          def chapter_wrapped_search_index(page_calculator, chapter_index)
            pages = Array(page_calculator.pages_data).each_with_index.filter_map do |page, index|
              next unless page && page[:chapter_index].to_i == chapter_index.to_i

              page_calculator.get_page(index) || page
            rescue Shoko::Error
              page
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
                    occurrence,
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
              matches << { start: index, end: index + needle.length }
              offset = index + [needle.length, 1].max
            end
            matches
          end

          def wrapped_search_match_score(text, occurrence, before_text:, match_start:, match_text:, after_text:, base_score:)
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

          def current_page_index
            @reader_state&.current_page_index
          rescue Shoko::Error
            nil
          end

          def resolve_result_page(page_calculator, page_index)
            return nil unless page_index

            page_calculator.get_page(page_index)
          rescue Shoko::Error
            nil
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

          def integer_result_value(entry, key)
            Integer(result_value(entry, key))
          rescue ArgumentError, TypeError
            nil
          end

          def extract_search_line_text(line)
            if line.is_a?(Shoko::Core::Models::DisplayLine)
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

          def monotonic_now
            @clock&.monotonic_now || Process.clock_gettime(Process::CLOCK_MONOTONIC)
          rescue Shoko::Error, SystemCallError
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          public

          def refresh_theme(theme_context:)
            color_mode = theme_context&.color_mode
            @in_book_search_ui_session&.refresh_theme(color_mode: color_mode)
          end

          def in_book_search_visible?
            @in_book_search_ui_session.visible? == true
          end
        end
      end
    end
  end
end
