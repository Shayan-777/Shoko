# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        ReaderSnapshotFields = %i[
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
          rendered_lines
          popup_menu
          in_book_search_popup
          search_landing_highlight
          annotations_overlay
          annotation_editor_overlay
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
          dictionary_popup
          dictionary_panel
          pending_progress
          pending_jump
          book_path
          loading_active
          loading_message
          loading_progress
        ].freeze

        # Immutable reader/session snapshot loaded from the state store.
        class ReaderSnapshot < Data.define(*ReaderSnapshotFields)
          DEFAULTS = {
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
            rendered_lines: {},
            popup_menu: nil,
            in_book_search_popup: nil,
            search_landing_highlight: nil,
            annotations_overlay: nil,
            annotation_editor_overlay: nil,
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
            dictionary_popup: nil,
            dictionary_panel: nil,
            pending_progress: nil,
            pending_jump: nil,
            book_path: nil,
            loading_active: false,
            loading_message: nil,
            loading_progress: nil,
          }.freeze

          def self.build(attributes = {})
            new(**DEFAULTS.merge(attributes))
          end

          def self.from_state(reader_state:, ui_state:)
            build(
              (reader_state || {}).merge(
                loading_active: ui_state&.dig(:loading_active) == true,
                loading_message: ui_state&.dig(:loading_message),
                loading_progress: ui_state&.dig(:loading_progress)
              )
            )
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def sidebar_visible?
            sidebar_visible == true
          end

          def loading_active?
            loading_active == true
          end

          def to_state_updates
            reader_updates = to_h.each_with_object({}) do |(field, value), updates|
              next if %i[loading_active loading_message loading_progress].include?(field)

              updates[[:reader, field]] = value
            end

            reader_updates.merge(
              [:ui, :loading_active] => loading_active,
              [:ui, :loading_message] => loading_message,
              [:ui, :loading_progress] => loading_progress
            )
          end
        end
      end
    end
  end
end
