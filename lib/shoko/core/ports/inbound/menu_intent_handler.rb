# frozen_string_literal: true

module Shoko
  module Core
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
