# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        class StateStore
          # Builds the canonical initial runtime state tree.
          class InitialStateBuilder
            def initialize(terminal_capabilities:)
              @terminal_capabilities = terminal_capabilities
            end

            def build
              {
                reader: {
                  current_chapter: 0,
                  left_page: 0,
                  right_page: 0,
                  single_page: 0,
                  current_page_index: 0,
                  mode: :read,
                  selection: nil,
                  message: nil,
                  running: true,
                  bookmarks: [],
                  annotations: [],
                  page_map: [],
                  total_pages: 0,
                  pages_per_chapter: [],
                  last_width: 0,
                  last_height: 0,
                  page_offset: 0,
                  dynamic_page_map: nil,
                  dynamic_total_pages: 0,
                  dynamic_chapter_starts: [],
                  last_dynamic_width: 0,
                  last_dynamic_height: 0,
                  rendered_lines: {},
                  popup_menu: nil,
                  in_book_search_popup: nil,
                  search_landing_highlight: nil,
                  annotations_overlay: nil,
                  annotation_editor_overlay: nil,
                  hovered_inline_link: nil,
                  sidebar_visible: false,
                  sidebar_active_tab: :toc,
                  sidebar_toc_selected: 0,
                  sidebar_annotations_selected: 0,
                  sidebar_bookmarks_selected: 0,
                  sidebar_toc_filter: nil,
                  sidebar_toc_filter_active: false,
                  sidebar_toc_collapsed: nil,
                },
                menu: {
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
                },
                config: {
                  view_mode: :single,
                  line_spacing: :normal,
                  page_numbering_mode: :dynamic,
                  theme: :default,
                  show_page_numbers: true,
                  highlight_quotes: true,
                  highlight_keywords: false,
                  prefetch_pages: 20,
                  kitty_images: @terminal_capabilities.kitty_graphics_supported?,
                  dictionary_source_lang: 'auto',
                  dictionary_target_lang: 'en',
                  dictionary_path: nil,
                  dictionary_backend: nil,
                },
                ui: {
                  terminal_width: 80,
                  terminal_height: 24,
                },
              }
            end
          end
        end
      end
    end
  end
end
