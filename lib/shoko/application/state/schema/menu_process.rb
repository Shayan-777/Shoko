# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Application-hosted menu process-state schema fragment.
        #
        # Owns the persisted slice of `state[:menu]`: the active mode, cursor
        # positions whose values drive use-case routing, text inputs that
        # become queries/values, and toggles that select what the next
        # application action will do (wipe-cache options, etc.).
        #
        # NOTE (Option-A compromise): some fields here — `selected`,
        # `browse_selected`, `*_cursor`, `translator_focus`, `rss_focus`,
        # `rss_scope`, `rss_zen_mode`, `rss_content_scroll`,
        # `selected_annotation*`, etc. — are conceptually UI presentation
        # state (list cursors, focus indicators, scroll positions). They
        # live here under Option A because the unified state store needs a
        # single application-controlled schema authority. The strict
        # separation where the UI owns its own store and the application
        # queries selections via a port is Option-B work (full
        # per-layer-store decomposition). Until then, the application
        # *reads* these fields directly and the UI *writes* them via the
        # menu session mutator.
        module MenuProcess
          PARTITION = :menu

          FIELDS = %i[
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
            rss_focus
            rss_scope
            rss_selected_feed_key
            rss_selected_article_id
            rss_content_scroll
            rss_feed_input
            rss_feed_input_cursor
            rss_filter_query
            rss_filter_cursor
            rss_zen_mode
            selected_annotation
            selected_annotation_book
            annotation_edit_text
            annotation_edit_cursor
            loading_path
            loading_index
            loading_mode
          ].freeze

          DEFAULTS = {
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
            dictionary_selected: 0,
            dictionary_query: '',
            dictionary_cursor: 0,
            translator_input_text: '',
            translator_input_cursor: 0,
            translator_source_lang: 'auto',
            translator_target_lang: 'en',
            translator_focus: :input,
            translator_dropdown_selected: 0,
            rss_focus: :feeds,
            rss_scope: :all,
            rss_selected_feed_key: '__all__',
            rss_selected_article_id: nil,
            rss_content_scroll: 0,
            rss_feed_input: '',
            rss_feed_input_cursor: 0,
            rss_filter_query: '',
            rss_filter_cursor: 0,
            rss_zen_mode: false,
            selected_annotation: nil,
            selected_annotation_book: nil,
            annotation_edit_text: '',
            annotation_edit_cursor: nil,
            loading_path: nil,
            loading_index: nil,
            loading_mode: nil,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.dup }
          end
        end
      end
    end
  end
end
