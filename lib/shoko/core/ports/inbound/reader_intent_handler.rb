# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Reader-facing inbound intent contract.
        module ReaderIntentHandler
          INTENT_SYMBOLS = %i[
            next_page
            prev_page
            scroll_down
            scroll_up
            next_chapter
            prev_chapter
            go_to_start
            go_to_end
            add_bookmark
            open_toc_sidebar
            open_bookmarks_sidebar
            open_annotations_sidebar
            open_annotations_overlay
            open_help_overlay
            close_help_overlay
            toggle_view_mode
            toggle_page_numbering_mode
            increase_line_spacing
            decrease_line_spacing
            toggle_sidebar
            sidebar_move_up
            sidebar_move_down
            sidebar_activate
            open_dictionary
            close_dictionary
            dictionary_insert_text
            dictionary_backspace
            dictionary_confirm
            dictionary_move_up
            dictionary_move_down
            dictionary_cycle_result
            dictionary_cycle_pair
            dictionary_swap_languages
            dictionary_toggle_fuzzy
            open_in_book_search
            close_in_book_search
            search_insert_text
            search_backspace
            search_confirm
            search_move_up
            search_move_down
            annotation_editor_insert_text
            annotation_editor_backspace
            annotation_editor_newline
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_move_down
            annotation_editor_save
            annotation_editor_cancel
            annotation_editor_spellcheck
            popup_move_up
            popup_move_down
            popup_confirm
            popup_cancel
            rebuild_pagination
            clear_pagination_cache
            quit_to_menu
            quit_application
          ].freeze

          def handle_reader_intent(_intent_symbol, _payload = nil)
            raise NotImplementedError, "#{self.class} must implement #handle_reader_intent"
          end
        end
      end
    end
  end
end
