# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        MenuSnapshotFields = %i[
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

        # Immutable menu/session snapshot loaded from the state store.
        class MenuSnapshot < Data.define(*MenuSnapshotFields)
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

          def self.build(attributes = {})
            new(**DEFAULTS.merge(attributes))
          end

          def self.from_state(menu_state)
            build(menu_state || {})
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def search_active?
            search_active == true
          end

          def loading_active?
            loading_active == true
          end

          def library_details_open?
            library_details_open == true
          end

          def wipe_cache_cached?
            wipe_cache_cached.nil? || wipe_cache_cached == true
          end

          def wipe_cache_downloads?
            wipe_cache_downloads == true
          end

          def wipe_cache_nuke?
            wipe_cache_nuke == true
          end

          def wipe_cache_annotations?
            wipe_cache_annotations == true
          end

          def wipe_cache_bookmarks?
            wipe_cache_bookmarks == true
          end

          def wipe_cache_config?
            wipe_cache_config == true
          end

          def wipe_cache_progress?
            wipe_cache_progress == true
          end

          def to_state_updates
            to_h.each_with_object({}) do |(field, value), updates|
              updates[[:menu, field]] = value
            end
          end
        end
      end
    end
  end
end
