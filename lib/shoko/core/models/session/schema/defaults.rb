# frozen_string_literal: true

require_relative 'version'
require_relative 'field_sets'
require_relative 'menu_fields'
require_relative 'runtime_fields'

module Shoko
  module Core
    module Models
      # Canonical session schema defaults.
      module Session
        # Canonical immutable defaults derived from the session schema.
        module Schema
          READER_DEFAULTS = {
            current_chapter: 0,
            left_page: 0,
            right_page: 0,
            single_page: 0,
            current_page: 0,
            current_page_index: 0,
            mode: :read,
            selection: nil,
            message: nil,
            running: true,
            bookmarks: [],
            annotations: [],
            page_map: [],
            total_pages: 0,
            total_chapters: 0,
            pages_per_chapter: [],
            last_width: 0,
            last_height: 0,
            page_offset: 0,
            dynamic_page_map: nil,
            dynamic_total_pages: 0,
            dynamic_chapter_starts: [],
            last_dynamic_width: 0,
            last_dynamic_height: 0,
            search_landing_highlight: nil,
            hovered_inline_link: nil,
            dictionary_visible: false,
            sidebar_visible: false,
            sidebar_active_tab: :toc,
            sidebar_prev_view_mode: nil,
            sidebar_toc_selected: 0,
            sidebar_annotations_selected: 0,
            sidebar_bookmarks_selected: 0,
            sidebar_toc_filter: nil,
            sidebar_toc_filter_active: false,
            sidebar_toc_collapsed: nil,
            pending_progress: nil,
            pending_jump: nil,
            book_path: nil,
            loading_active: false,
            loading_message: nil,
            loading_progress: nil,
          }.freeze

          READER_SESSION_DEFAULTS = READER_DEFAULTS.slice(*READER_SESSION_FIELDS).freeze
          READER_PAGINATION_DEFAULTS = READER_DEFAULTS.slice(*READER_PAGINATION_FIELDS).freeze
          READER_VIEW_STATE_DEFAULTS = READER_DEFAULTS.slice(*READER_VIEW_STATE_FIELDS).freeze

          MENU_DEFAULTS = {
            selected: 0,
            mode: :menu,
            browse_selected: 0,
            library_details_open: false,
            settings_selected: 1,
            wipe_cache_cached: true,
            wipe_cache_downloads: false,
            wipe_cache_nuke: false,
            wipe_cache_annotations: false,
            wipe_cache_bookmarks: false,
            wipe_cache_config: false,
            wipe_cache_progress: false,
            search_query: '',
            search_cursor: 0,
            search_active: false,
            download_query: '',
            download_cursor: 0,
            download_source_selected: 0,
            download_selected: 0,
            download_results: [],
            download_count: 0,
            download_next: nil,
            download_prev: nil,
            download_status: :idle,
            download_message: '',
            download_progress: 0.0,
            dictionary_selected: 0,
            dictionary_query: '',
            dictionary_cursor: 0,
            dictionary_results: [],
            dictionary_status: :idle,
            dictionary_message: '',
            dictionary_progress: 0.0,
            translator_input_text: '',
            translator_input_cursor: 0,
            translator_output_text: '',
            translator_source_lang: 'auto',
            translator_target_lang: 'en',
            translator_detected_source_lang: nil,
            translator_languages: [],
            translator_status: :idle,
            translator_message: 'Type text to translate.',
            translator_focus: :input,
            translator_dropdown_selected: 0,
            annotations_all: {},
            selected_annotation: nil,
            selected_annotation_book: nil,
            annotation_edit_text: '',
            annotation_edit_cursor: nil,
            loading_path: nil,
            loading_active: false,
            loading_progress: nil,
            loading_message: nil,
            loading_index: nil,
            loading_mode: nil,
          }.freeze

          MENU_SESSION_DEFAULTS = MENU_DEFAULTS.slice(*MENU_SESSION_FIELDS).freeze
          MENU_TRANSIENT_DEFAULTS = MENU_DEFAULTS.slice(*MENU_TRANSIENT_FIELDS).freeze

          CONFIG_DEFAULTS = {
            schema_version: CONFIG_SCHEMA_VERSION,
            view_mode: :single,
            line_spacing: :normal,
            download_source: :gutendex,
            page_numbering_mode: :dynamic,
            theme: :default,
            show_page_numbers: true,
            highlight_quotes: true,
            highlight_keywords: false,
            prefetch_pages: 20,
            kitty_images: false,
            dictionary_source_lang: 'auto',
            dictionary_target_lang: 'en',
            dictionary_path: nil,
            dictionary_backend: nil,
          }.freeze

          UI_DEFAULTS = {
            terminal_width: 80,
            terminal_height: 24,
            loading_active: false,
            loading_message: nil,
            loading_progress: nil,
          }.freeze
        end
      end
    end
  end
end
