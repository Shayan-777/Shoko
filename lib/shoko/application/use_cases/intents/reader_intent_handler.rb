# frozen_string_literal: true

require_relative '../../../core/ports/inbound/reader_intent_handler'

module Shoko
  module Application
    module UseCases
      module Intents
        # Application-level reader intent dispatcher.
        class ReaderIntentHandler
          include Shoko::Core::Ports::Inbound::ReaderIntentHandler

          def initialize(reader_controller:)
            @reader_controller = reader_controller
          end

          def command_logger
            @reader_controller.command_logger
          end

          def handle_reader_intent(intent_symbol, payload = nil)
            key = payload&.key

            case intent_symbol.to_sym
            when :annotation_editor_backspace then @reader_controller.annotation_editor_backspace
            when :annotation_editor_cancel then @reader_controller.annotation_editor_cancel
            when :annotation_editor_enter then @reader_controller.annotation_editor_enter
            when :annotation_editor_insert_char_if_printable then @reader_controller.annotation_editor_insert_char_if_printable(key)
            when :annotation_editor_move_down then @reader_controller.annotation_editor_move_down
            when :annotation_editor_move_left then @reader_controller.annotation_editor_move_left
            when :annotation_editor_move_right then @reader_controller.annotation_editor_move_right
            when :annotation_editor_move_up then @reader_controller.annotation_editor_move_up
            when :annotation_editor_save then @reader_controller.annotation_editor_save
            when :decrease_line_spacing then @reader_controller.decrease_line_spacing
            when :dictionary_backspace then @reader_controller.dictionary_backspace
            when :dictionary_cancel then @reader_controller.dictionary_cancel
            when :dictionary_confirm then @reader_controller.dictionary_confirm
            when :dictionary_cycle_pair then @reader_controller.dictionary_cycle_pair
            when :dictionary_cycle_result then @reader_controller.dictionary_cycle_result
            when :dictionary_insert_char_if_printable then @reader_controller.dictionary_insert_char_if_printable(key)
            when :dictionary_scroll_down then @reader_controller.dictionary_scroll_down
            when :dictionary_scroll_up then @reader_controller.dictionary_scroll_up
            when :dictionary_swap_languages then @reader_controller.dictionary_swap_languages
            when :dictionary_toggle_fuzzy then @reader_controller.dictionary_toggle_fuzzy
            when :handle_popup_action_key then @reader_controller.handle_popup_action_key(key)
            when :handle_popup_cancel then @reader_controller.handle_popup_cancel(key)
            when :handle_popup_navigation then @reader_controller.handle_popup_navigation(key)
            when :help_exit_to_read then @reader_controller.help_exit_to_read
            when :in_book_search_backspace then @reader_controller.in_book_search_backspace
            when :in_book_search_cancel then @reader_controller.in_book_search_cancel
            when :in_book_search_confirm then @reader_controller.in_book_search_confirm
            when :in_book_search_down then @reader_controller.in_book_search_down
            when :in_book_search_insert_char_if_printable then @reader_controller.in_book_search_insert_char_if_printable(key)
            when :in_book_search_up then @reader_controller.in_book_search_up
            when :increase_line_spacing then @reader_controller.increase_line_spacing
            when :invalidate_pagination_cache then @reader_controller.invalidate_pagination_cache
            when :open_annotations then @reader_controller.open_annotations
            when :open_annotations_tab then @reader_controller.open_annotations_tab
            when :open_bookmarks then @reader_controller.open_bookmarks
            when :open_in_book_search then @reader_controller.open_in_book_search
            when :open_toc then @reader_controller.open_toc
            when :quit_application then @reader_controller.quit_application
            when :quit_to_menu then @reader_controller.quit_to_menu
            when :read_confirm_or_sidebar then @reader_controller.read_confirm_or_sidebar
            when :read_scroll_down_or_sidebar then @reader_controller.read_scroll_down_or_sidebar
            when :read_scroll_up_or_sidebar then @reader_controller.read_scroll_up_or_sidebar
            when :read_space_or_sidebar_toggle then @reader_controller.read_space_or_sidebar_toggle
            when :rebuild_pagination then @reader_controller.rebuild_pagination
            when :show_help then @reader_controller.show_help
            when :toggle_page_numbering_mode then @reader_controller.toggle_page_numbering_mode
            when :toggle_view_mode then @reader_controller.toggle_view_mode
            else
              raise ArgumentError, "Unsupported reader intent: #{intent_symbol}"
            end
          end
        end
      end
    end
  end
end
