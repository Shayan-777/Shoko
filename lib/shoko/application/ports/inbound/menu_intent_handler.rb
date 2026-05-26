# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Inbound
        # Menu-facing inbound intent contract.
        module MenuIntentHandler
          INTENT_SYMBOLS = %i[
            move_menu_selection_up
            move_menu_selection_down
            activate_menu_selection
            switch_to_menu_mode
            switch_to_browse_mode
            switch_to_search_mode
            open_rss_reader_mode
            close_rss_reader_mode
            move_browse_selection_up
            move_browse_selection_down
            open_selected_book
            browse_insert_text
            browse_backspace
            browse_delete
            move_library_selection_up
            move_library_selection_down
            activate_library_selection
            toggle_library_details
            move_settings_selection_up
            move_settings_selection_down
            activate_settings_selection
            open_dictionary_mode
            close_dictionary_mode
            refresh_dictionary_results
            move_dictionary_selection_up
            move_dictionary_selection_down
            activate_dictionary_selection
            dictionary_query_insert_text
            dictionary_query_backspace
            dictionary_query_delete
            submit_dictionary_query
            open_download_mode
            close_download_mode
            open_download_source_mode
            close_download_source_mode
            refresh_download_results
            move_download_selection_up
            move_download_selection_down
            move_download_source_selection_up
            move_download_source_selection_down
            activate_download_selection
            activate_download_source_selection
            download_query_insert_text
            download_query_backspace
            download_query_delete
            submit_download_query
            download_next_page
            download_prev_page
            close_translator_mode
            close_translator_dropdown
            translator_cycle_focus
            translator_activate_focus
            translator_swap_languages
            translator_input_insert_text
            translator_input_backspace
            translator_input_delete
            move_translator_language_selection_up
            move_translator_language_selection_down
            activate_translator_language_selection
            rss_reader_focus_left
            rss_reader_focus_right
            rss_reader_cycle_focus
            rss_reader_cycle_focus_back
            rss_reader_activate_selection
            rss_reader_move_up
            rss_reader_move_down
            rss_reader_go_top
            rss_reader_go_bottom
            rss_reader_page_down
            rss_reader_page_up
            rss_reader_sync
            rss_reader_toggle_zen
            rss_reader_show_all
            rss_reader_show_unread
            rss_reader_show_starred
            rss_reader_mark_read
            rss_reader_mark_unread
            rss_reader_mark_starred
            rss_reader_unstar
            rss_reader_open_add_feed
            rss_reader_add_feed_insert_text
            rss_reader_add_feed_backspace
            rss_reader_add_feed_delete
            rss_reader_submit_add_feed
            rss_reader_open_filter
            rss_reader_filter_insert_text
            rss_reader_filter_backspace
            rss_reader_filter_delete
            rss_reader_submit_filter
            rss_reader_remove_feed
            open_annotations_mode
            move_annotation_selection_up
            move_annotation_selection_down
            activate_annotation_selection
            open_selected_annotation
            edit_selected_annotation
            delete_selected_annotation
            annotation_editor_insert_text
            annotation_editor_backspace
            annotation_editor_newline
            annotation_editor_move_left
            annotation_editor_move_right
            annotation_editor_move_up
            annotation_editor_move_down
            annotation_editor_save
            annotation_editor_cancel
            quit_application
          ].freeze

          def handle_menu_intent(_intent_symbol, _payload = nil)
            raise NotImplementedError, "#{self.class} must implement #handle_menu_intent"
          end
        end
      end
    end
  end
end
