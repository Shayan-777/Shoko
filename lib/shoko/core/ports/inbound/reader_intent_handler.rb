# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Reader-facing inbound intent contract.
        module ReaderIntentHandler
          INTENT_SYMBOLS = %i[
            annotation_editor_backspace
            annotation_editor_cancel
            annotation_editor_enter
            annotation_editor_insert_char_if_printable
            annotation_editor_move_down
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_save
            annotation_editor_spellcheck
            decrease_line_spacing
            dictionary_backspace
            dictionary_cancel
            dictionary_confirm
            dictionary_cycle_pair
            dictionary_cycle_result
            dictionary_insert_char_if_printable
            dictionary_scroll_down
            dictionary_scroll_up
            dictionary_swap_languages
            dictionary_toggle_fuzzy
            handle_popup_action_key
            handle_popup_cancel
            handle_popup_navigation
            help_exit_to_read
            in_book_search_backspace
            in_book_search_cancel
            in_book_search_confirm
            in_book_search_down
            in_book_search_insert_char_if_printable
            in_book_search_up
            increase_line_spacing
            invalidate_pagination_cache
            open_annotations
            open_annotations_tab
            open_bookmarks
            open_in_book_search
            open_toc
            quit_application
            quit_to_menu
            read_confirm_or_sidebar
            read_scroll_down_or_sidebar
            read_scroll_up_or_sidebar
            read_space_or_sidebar_toggle
            rebuild_pagination
            show_help
            toggle_page_numbering_mode
            toggle_view_mode
          ].freeze

          def handle_reader_intent(_intent_symbol, _payload = nil)
            raise NotImplementedError, "#{self.class} must implement #handle_reader_intent"
          end

          def command_logger
            raise NotImplementedError, "#{self.class} must implement #command_logger"
          end
        end
      end
    end
  end
end
