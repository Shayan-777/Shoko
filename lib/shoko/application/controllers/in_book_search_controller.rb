# frozen_string_literal: true

module Shoko
  module Application::Controllers
    # Handles in-book full text search popup lifecycle and input interactions.
    class InBookSearchController
      def initialize(reader_state:, state_writer:, search_service:,
                     input_controller: nil, reader_controller: nil, state_controller: nil,
                     notification_service: nil, logger: nil, in_book_search_ui_session: nil)
        @reader_state = reader_state
        @state_writer = state_writer
        @search_service = search_service
        @input_controller = input_controller
        @reader_controller = reader_controller
        @state_controller = state_controller
        @notification_service = notification_service
        @logger = logger
        @in_book_search_ui_session = in_book_search_ui_session
      end

      attr_writer :input_controller, :state_controller

      def open_in_book_search(_key = nil)
        result = @in_book_search_ui_session&.open(query: '', results: [], total_matches: 0)
        return :pass unless session_ok?(result)

        activate_search_mode
        set_message('In-book search: type query, press Enter to search', 2)
        :handled
      rescue StandardError => e
        @logger&.debug('in_book_search.open_failed', error: e.message)
        :pass
      end

      def close_in_book_search(_key = nil)
        mode = @reader_state.respond_to?(:mode) ? @reader_state.mode : :read
        return :pass unless @in_book_search_ui_session&.visible? || mode == :in_book_search

        result = @in_book_search_ui_session.close
        return :pass unless session_ok?(result)

        deactivate_search_mode
        :handled
      rescue StandardError => e
        @logger&.debug('in_book_search.close_failed', error: e.message)
        :pass
      end

      def in_book_search_up(_key = nil)
        result = @in_book_search_ui_session&.scroll_up
        session_ok?(result) ? :handled : :pass
      end

      def in_book_search_down(_key = nil)
        result = @in_book_search_ui_session&.scroll_down
        session_ok?(result) ? :handled : :pass
      end

      def in_book_search_insert_char(char)
        result = session_payload(@in_book_search_ui_session&.insert_char(char))
        process_in_book_search_session_result(result)
      end

      def in_book_search_backspace(_key = nil)
        result = session_payload(@in_book_search_ui_session&.backspace)
        process_in_book_search_session_result(result)
      end

      def in_book_search_confirm(_key = nil)
        result = session_payload(@in_book_search_ui_session&.confirm)
        process_in_book_search_session_result(result)
      end

      def in_book_search_cancel(_key = nil)
        result = session_payload(@in_book_search_ui_session&.cancel)
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
        result.is_a?(Shoko::Application::Ui::SessionOutcome)
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
      rescue StandardError => e
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
        line_offset = (result_entry[:line_index] || result_entry['line_index']).to_i

        destination = jump_destination(chapter_index, line_offset)
        return :pass unless destination

        close_in_book_search
        label = result_entry[:chapter_title].to_s.strip
        label = "Chapter #{chapter_index + 1}" if label.empty?
        set_message("Opened result in #{label}", 2)
        @reader_controller&.draw_screen if @reader_controller&.respond_to?(:draw_screen)
        :handled
      rescue StandardError => e
        @logger&.debug('in_book_search.open_result_failed', error: e.message)
        :pass
      end

      def jump_destination(chapter_index, line_offset)
        controller = resolve_state_controller
        return false unless controller&.respond_to?(:jump_to_chapter_offset)

        controller.jump_to_chapter_offset(chapter_index, line_offset)
        true
      end

      def resolve_state_controller
        return @state_controller if @state_controller
        return nil unless @reader_controller&.respond_to?(:state_controller)

        @reader_controller.state_controller
      rescue StandardError
        nil
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

      public

      def in_book_search_visible?
        @in_book_search_ui_session&.visible? == true
      end

      def set_message(text, duration = 2)
        if @notification_service
          @notification_service.set_message(text, duration)
        else
          @state_writer.update_reader(message: text)
        end
      rescue StandardError
        @state_writer.update_reader(message: text)
      end
    end
  end
end
