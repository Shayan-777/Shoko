# frozen_string_literal: true

require_relative 'base_command'

module Shoko
  module Application
    module Commands
      # Reader UI intent commands routed through stable controller interfaces.
      class ReaderIntentCommand < BaseCommand
        def initialize(action)
          @action = action
          super(name: "reader_intent_#{action}", description: "Reader intent #{action}")
        end

        protected

        def perform(context, params = {})
          ui = context.ui_controller

          case @action
          when :increase_line_spacing
            ui.increase_line_spacing
          when :decrease_line_spacing
            ui.decrease_line_spacing
          when :open_in_book_search
            ui.open_in_book_search
          when :close_in_book_search
            ui.in_book_search_cancel
          when :open_annotations_tab
            ui.open_annotations_tab
          when :rebuild_pagination
            context.rebuild_pagination
          when :invalidate_pagination_cache
            context.invalidate_pagination_cache
          when :exit_popup_menu
            context.cleanup_popup_state
          when :close_dictionary
            ui.dictionary_cancel
          when :dictionary_scroll_up
            ui.dictionary_scroll_up
          when :dictionary_scroll_down
            ui.dictionary_scroll_down
          when :dictionary_toggle_fuzzy
            ui.dictionary_toggle_fuzzy
          when :dictionary_cycle_result
            ui.dictionary_cycle_result
          when :dictionary_cycle_pair
            ui.dictionary_cycle_pair
          when :dictionary_backspace
            ui.dictionary_backspace
          when :dictionary_confirm
            ui.dictionary_confirm
          when :dictionary_cancel
            ui.dictionary_cancel
          when :dictionary_tab
            ui.dictionary_tab
          when :dictionary_swap_languages
            ui.dictionary_swap_languages
          when :dictionary_insert_char
            handle_dictionary_insert(ui, params)
          when :in_book_search_up
            ui.in_book_search_up
          when :in_book_search_down
            ui.in_book_search_down
          when :in_book_search_backspace
            ui.in_book_search_backspace
          when :in_book_search_confirm
            ui.in_book_search_confirm
          when :in_book_search_cancel
            ui.in_book_search_cancel
          when :in_book_search_insert_char
            handle_search_insert(ui, params)
          else
            raise ExecutionError.new("Unknown reader intent action: #{@action}", command_name: name)
          end
        end

        private

        def handle_dictionary_insert(ui, params)
          key = params[:key].to_s
          return :pass if key.empty?

          ui.dictionary_insert_char(key)
        end

        def handle_search_insert(ui, params)
          key = params[:key].to_s
          return :pass if key.empty?

          ui.in_book_search_insert_char(key)
        end
      end
    end
  end
end
