# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        # Canonical runtime/session schema and defaults.
        module Schema
          module_function

          CONFIG_SCHEMA_VERSION = 2

          READER_SESSION_FIELDS = %i[
            current_chapter
            left_page
            right_page
            single_page
            current_page
            current_page_index
            mode
            selection
            message
            running
            bookmarks
            annotations
            total_chapters
            pending_progress
            pending_jump
            book_path
          ].freeze

          READER_PAGINATION_FIELDS = %i[
            page_map
            total_pages
            pages_per_chapter
            last_width
            last_height
            page_offset
            dynamic_page_map
            dynamic_total_pages
            dynamic_chapter_starts
            last_dynamic_width
            last_dynamic_height
          ].freeze

          READER_VIEW_STATE_FIELDS = %i[
            search_landing_highlight
            hovered_inline_link
            dictionary_visible
            sidebar_visible
            sidebar_active_tab
            sidebar_prev_view_mode
            sidebar_toc_selected
            sidebar_annotations_selected
            sidebar_bookmarks_selected
            sidebar_toc_filter
            sidebar_toc_filter_active
            sidebar_toc_collapsed
            loading_active
            loading_message
            loading_progress
          ].freeze

          READER_FIELDS = %i[
            current_chapter
            left_page
            right_page
            single_page
            current_page
            current_page_index
            mode
            selection
            message
            running
            bookmarks
            annotations
            page_map
            total_pages
            total_chapters
            pages_per_chapter
            last_width
            last_height
            page_offset
            dynamic_page_map
            dynamic_total_pages
            dynamic_chapter_starts
            last_dynamic_width
            last_dynamic_height
            search_landing_highlight
            hovered_inline_link
            dictionary_visible
            sidebar_visible
            sidebar_active_tab
            sidebar_prev_view_mode
            sidebar_toc_selected
            sidebar_annotations_selected
            sidebar_bookmarks_selected
            sidebar_toc_filter
            sidebar_toc_filter_active
            sidebar_toc_collapsed
            pending_progress
            pending_jump
            book_path
            loading_active
            loading_message
            loading_progress
          ].freeze

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
            annotations_all
            loading_active
            loading_progress
            loading_message
          ].freeze

          CONFIG_FIELDS = %i[
            schema_version
            view_mode
            line_spacing
            download_source
            page_numbering_mode
            theme
            show_page_numbers
            highlight_quotes
            highlight_keywords
            prefetch_pages
            kitty_images
            dictionary_source_lang
            dictionary_target_lang
            dictionary_path
            dictionary_backend
          ].freeze

          UI_FIELDS = %i[
            terminal_width
            terminal_height
            loading_active
            loading_message
            loading_progress
          ].freeze

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

          def initial_runtime_state(terminal_capabilities:)
            {
              reader: reader_state_defaults,
              menu: menu_state_defaults,
              config: config_state_defaults(terminal_capabilities: terminal_capabilities),
              ui: ui_state_defaults,
            }
          end

          def reader_state_defaults
            READER_DEFAULTS.except(*ui_backed_reader_fields)
          end

          def menu_state_defaults
            MENU_DEFAULTS.dup
          end

          def config_state_defaults(terminal_capabilities:)
            CONFIG_DEFAULTS.merge(
              kitty_images: terminal_capabilities.kitty_graphics_supported?
            )
          end

          def ui_state_defaults
            UI_DEFAULTS.dup
          end

          def ui_backed_reader_fields
            %i[loading_active loading_message loading_progress].freeze
          end
        end
      end
    end
  end
end
