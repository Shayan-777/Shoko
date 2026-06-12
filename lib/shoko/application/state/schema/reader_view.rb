# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Schema fragment for the reader view-state slice of `state[:reader]`.
        #
        # The fields named here are reader UI-presentation state (overlay
        # visibility/tab/cursor, dictionary panel hint, hover/search
        # highlights). This is the reader's UI-state fragment of the single
        # application-owned store, and that placement is by design: the reader
        # keeps one central, schema-partitioned store as its source of truth
        # (the "single store" pattern), with UI-presentation state in the
        # view/UI-designated fragments (this one and `UiGlobals`). The UI
        # writes these fields and observes them through outbound ports; there
        # is no separate per-layer UI store planned.
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
            popup_menu_selected
            dictionary_visible
            dictionary_setup_active
            dictionary_query
            dictionary_results_query
            dictionary_result
            dictionary_entry_index
            dictionary_selected_index
            dictionary_fuzzy_mode
            dictionary_fuzzy_matches
            annotations_overlay_selected
            toc_query
            toc_selected_index
            toc_visible_entries
            translator_query
            translator_results_query
            translator_result
            translator_source_lang
            translator_target_lang
            translator_languages
            translator_picker_side
            translator_picker_query
            translator_picker_index
            translator_scroll
            translator_cursor
            notes_selected_index
            notes_composing
            notes_draft
            notes_cursor
            notes_editing_id
            notes_editing_text
            notes_editing_range
            notes_editing_chapter
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
            popup_menu_selected: 0,
            dictionary_visible: false,
            dictionary_setup_active: false,
            dictionary_query: '',
            dictionary_results_query: '',
            dictionary_result: nil,
            dictionary_entry_index: 0,
            dictionary_selected_index: 0,
            dictionary_fuzzy_mode: false,
            dictionary_fuzzy_matches: [],
            annotations_overlay_selected: 0,
            toc_query: '',
            toc_selected_index: 0,
            toc_visible_entries: [],
            translator_query: '',
            translator_results_query: '',
            translator_result: nil,
            translator_source_lang: 'auto',
            translator_target_lang: 'en',
            translator_languages: [],
            translator_picker_side: nil,
            translator_picker_query: '',
            translator_picker_index: 0,
            translator_scroll: 0,
            translator_cursor: 0,
            notes_selected_index: 0,
            notes_composing: false,
            notes_draft: '',
            notes_cursor: 0,
            notes_editing_id: nil,
            notes_editing_text: '',
            notes_editing_range: nil,
            notes_editing_chapter: nil,
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
