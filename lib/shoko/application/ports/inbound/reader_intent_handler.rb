# frozen_string_literal: true

module Shoko
  module Application
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
            open_annotations_overlay
            open_help_overlay
            close_help_overlay
            toggle_view_mode
            toggle_page_numbering_mode
            increase_line_spacing
            decrease_line_spacing
            open_dictionary
            close_dictionary
            edit_reader_dictionary_query
            dictionary_confirm
            dictionary_move_up
            dictionary_move_down
            dictionary_cycle_result
            dictionary_cycle_pair
            dictionary_swap_languages
            dictionary_toggle_fuzzy
            open_in_book_search
            close_in_book_search
            edit_in_book_search
            search_confirm
            search_move_up
            search_move_down
            open_toc
            close_toc
            edit_toc_filter
            toc_confirm
            toc_move_up
            toc_move_down
            open_translator
            close_translator
            edit_translator
            translator_confirm
            translator_submit
            translator_cursor_move
            translator_cycle_picker
            translator_open_picker
            translator_paste_source
            translator_copy_translation
            translator_swap_languages
            open_notes
            close_notes
            notes_move_up
            notes_move_down
            notes_confirm
            notes_edit
            notes_new
            notes_delete
            edit_note
            note_cursor_move
            edit_annotation_text
            move_annotation_cursor
            annotation_editor_save
            annotation_editor_cancel
            annotation_editor_spellcheck
            annotation_editor_confirm
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
