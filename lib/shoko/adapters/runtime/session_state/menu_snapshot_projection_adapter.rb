# frozen_string_literal: true

require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/models/session/menu_session_snapshot'
require_relative '../../../core/models/session/menu_transient_snapshot'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Read-only composite menu adapter that merges session and transient projections.
        class MenuSnapshotProjectionAdapter
          Shoko::Core::Models::Session::MenuSnapshotFields.each do |field|
            define_method(field) { load.to_h.fetch(field) }
          end

          def initialize(state:, menu_session_store:, menu_transient_store:)
            @state = state
            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
            @snapshot_root = nil
            @snapshot = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            snapshot = Shoko::Core::Models::Session::MenuSnapshot.build(
              @menu_session_store.load.to_h.merge(@menu_transient_store.load.to_h)
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def snapshot
            load
          end

          def search_active?
            load.search_active?
          end

          def loading_active?
            load.loading_active?
          end

          def library_details_open?
            load.library_details_open?
          end

          def wipe_cache_cached?
            load.wipe_cache_cached?
          end

          def wipe_cache_downloads?
            load.wipe_cache_downloads?
          end

          def wipe_cache_nuke?
            load.wipe_cache_nuke?
          end

          def wipe_cache_annotations?
            load.wipe_cache_annotations?
          end

          def wipe_cache_bookmarks?
            load.wipe_cache_bookmarks?
          end

          def wipe_cache_config?
            load.wipe_cache_config?
          end

          def wipe_cache_progress?
            load.wipe_cache_progress?
          end

          def current_menu_mode
            load.current_menu_mode
          end

          def selected_library_index
            load.selected_library_index
          end

          def selected_annotation_record
            load.selected_annotation_record
          end

          def selected_annotation_book_path
            load.selected_annotation_book_path
          end

          def annotation_editor_text
            load.annotation_editor_text
          end

          def dictionary_entries
            load.dictionary_entries
          end
        end
      end
    end
  end
end
