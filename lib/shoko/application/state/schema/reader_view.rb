# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Schema fragment for the reader view-state slice of `state[:reader]`.
        #
        # The fields named here describe presentation concerns owned by the
        # UI layer (sidebar visibility/tab/cursor, dictionary panel hint,
        # hover/search highlights). The fragment is hosted in
        # `Application::State::Schema` for a deliberate reason: the unified
        # state store needs a single, application-controlled schema authority
        # to initialise the in-memory hash. The full per-layer-store
        # decomposition where the UI owns its own store is future work
        # (Option B in the refactor plan); under Option A the application
        # hosts the field set on the UI's behalf.
        #
        # Loading-mirror fields are kept here for default-set reference but
        # are excluded from `contribute` because they live canonically in
        # `state[:ui]` (see `Schema::UiGlobals`); the reader-view store
        # adapter merges them on read.
        module ReaderView
          PARTITION = :reader

          FIELDS = %i[
            search_landing_highlight
            search_query
            search_results
            search_results_query
            search_selected_index
            search_total_matches
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
            annotation_editor_note
            annotation_editor_cursor
            annotation_editor_selected_text
            annotation_editor_range
            annotation_editor_chapter_index
            annotation_editor_annotation_id
            loading_active
            loading_message
            loading_progress
          ].freeze

          LOADING_FIELDS = %i[loading_active loading_message loading_progress].freeze

          DEFAULTS = {
            search_landing_highlight: nil,
            search_query: '',
            search_results: [],
            search_results_query: '',
            search_selected_index: 0,
            search_total_matches: 0,
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
            annotation_editor_note: '',
            annotation_editor_cursor: 0,
            annotation_editor_selected_text: '',
            annotation_editor_range: nil,
            annotation_editor_chapter_index: nil,
            annotation_editor_annotation_id: nil,
            loading_active: false,
            loading_message: nil,
            loading_progress: nil,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.except(*LOADING_FIELDS) }
          end
        end
      end
    end
  end
end
