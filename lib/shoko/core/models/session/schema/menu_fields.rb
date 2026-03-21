# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        # Canonical menu session field lists.
        module Schema
          MENU_FIELDS = %i[
            selected
            mode
            browse_selected
            library_details_open
            settings_selected
            wipe_cache_cached
            wipe_cache_downloads
            wipe_cache_nuke
            wipe_cache_annotations
            wipe_cache_bookmarks
            wipe_cache_config
            wipe_cache_progress
            search_query
            search_cursor
            search_active
            download_query
            download_cursor
            download_source_selected
            download_selected
            download_results
            download_count
            download_next
            download_prev
            download_status
            download_message
            download_progress
            dictionary_selected
            dictionary_query
            dictionary_cursor
            dictionary_results
            dictionary_status
            dictionary_message
            dictionary_progress
            translator_input_text
            translator_input_cursor
            translator_output_text
            translator_source_lang
            translator_target_lang
            translator_detected_source_lang
            translator_languages
            translator_status
            translator_message
            translator_focus
            translator_dropdown_selected
            annotations_all
            selected_annotation
            selected_annotation_book
            annotation_edit_text
            annotation_edit_cursor
            loading_path
            loading_active
            loading_progress
            loading_message
            loading_index
            loading_mode
          ].freeze

          MENU_SESSION_FIELDS = %i[
            selected
            mode
            browse_selected
            library_details_open
            settings_selected
            wipe_cache_cached
            wipe_cache_downloads
            wipe_cache_nuke
            wipe_cache_annotations
            wipe_cache_bookmarks
            wipe_cache_config
            wipe_cache_progress
            search_query
            search_cursor
            search_active
            download_query
            download_cursor
            download_source_selected
            download_selected
            dictionary_selected
            dictionary_query
            dictionary_cursor
            translator_input_text
            translator_input_cursor
            translator_source_lang
            translator_target_lang
            translator_focus
            translator_dropdown_selected
            selected_annotation
            selected_annotation_book
            annotation_edit_text
            annotation_edit_cursor
            loading_path
            loading_index
            loading_mode
          ].freeze

          MENU_TRANSIENT_FIELDS = %i[
            download_results
            download_count
            download_next
            download_prev
            download_status
            download_message
            download_progress
            dictionary_results
            dictionary_status
            dictionary_message
            dictionary_progress
            translator_output_text
            translator_detected_source_lang
            translator_languages
            translator_status
            translator_message
            annotations_all
            loading_active
            loading_progress
            loading_message
          ].freeze
        end
      end
    end
  end
end
