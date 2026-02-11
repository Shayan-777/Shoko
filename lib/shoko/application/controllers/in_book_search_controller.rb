# frozen_string_literal: true

require_relative '../../core/services/in_book_search_service'

module Shoko
  module Application::Controllers
    # Handles in-book full text search popup lifecycle and input interactions.
    class InBookSearchController
      def initialize(reader_state:, state_writer:, ui_component_factory: nil, document: nil,
                     input_controller: nil, reader_controller: nil, state_controller: nil,
                     notification_service: nil, logger: nil, search_service: nil)
        @reader_state = reader_state
        @state_writer = state_writer
        @ui_component_factory = ui_component_factory
        @document = document
        @input_controller = input_controller
        @reader_controller = reader_controller
        @state_controller = state_controller
        @notification_service = notification_service
        @logger = logger
        @search_service = search_service
      end

      attr_writer :input_controller, :state_controller

      def open_in_book_search(_key = nil)
        popup = ensure_popup
        return :pass unless popup

        popup.show(query: '', results: [], total_matches: 0)
        @state_writer.update_reader(
          in_book_search_popup: popup,
          mode: :in_book_search,
          popup_menu: nil
        )
        activate_search_mode
        set_message('In-book search: type query, press Enter to search', 2)
        :handled
      rescue StandardError => e
        @logger&.debug('in_book_search.open_failed', error: e.message)
        :pass
      end

      def close_in_book_search(_key = nil)
        popup = @reader_state.in_book_search_popup
        mode = @reader_state.respond_to?(:mode) ? @reader_state.mode : :read
        return :pass unless popup || mode == :in_book_search

        popup&.hide
        @state_writer.update_reader(
          in_book_search_popup: nil,
          mode: :read
        )
        deactivate_search_mode
        :handled
      rescue StandardError => e
        @logger&.debug('in_book_search.close_failed', error: e.message)
        :pass
      end

      def in_book_search_up(_key = nil)
        handle_in_book_search_key("\e[A")
      end

      def in_book_search_down(_key = nil)
        handle_in_book_search_key("\e[B")
      end

      def handle_in_book_search_key(key)
        popup = active_popup
        return :pass unless popup

        result = popup.handle_key(key)
        return :pass unless result

        case result[:type]
        when :close
          close_in_book_search
        when :query_change
          :handled
        when :submit_query
          query = result[:query].to_s
          apply_search(query, popup)
          :handled
        when :open_result
          open_result(result[:result])
        when :scroll
          :handled
        else
          :pass
        end
      rescue StandardError => e
        @logger&.debug('in_book_search.handle_key_failed', key: key.to_s, error: e.message)
        :pass
      end

      private

      def apply_search(query, popup)
        result = search_service.search(query)
        popup.update(
          query: result.query,
          results: result.matches,
          total_matches: result.total_matches,
          results_query: result.query
        )
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

      def search_service
        @search_service ||= Shoko::Core::Services::InBookSearchService.new(
          document: @document,
          logger: @logger
        )
      end

      def active_popup
        popup = @reader_state.in_book_search_popup
        return nil unless popup.respond_to?(:visible?) && popup.visible?

        popup
      rescue StandardError
        nil
      end

      def ensure_popup
        popup = @reader_state.in_book_search_popup
        popup ||= @ui_component_factory&.in_book_search_popup
        popup
      end

      def activate_search_mode
        @input_controller&.enter_modal_mode(:in_book_search)
      end

      def deactivate_search_mode
        @input_controller&.exit_modal_mode(:in_book_search)
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
