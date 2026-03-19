# frozen_string_literal: true

require_relative '../../../core/models/session/menu_session_snapshot'
require_relative '../../../core/ports/outbound/menu_session_store'
require_relative 'branch_snapshot_support'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed menu session store over ObserverStateStore.
        class MenuSessionStoreAdapter
          include Shoko::Core::Ports::Outbound::MenuSessionStore
          include BranchSnapshotSupport

          Shoko::Core::Models::Session::MenuSessionSnapshotFields.each do |field|
            define_method(field) do
              @state.peek_at(:menu, field)
            end
          end

          def initialize(state)
            @state = state
            @snapshot_root = nil
            @snapshot = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            snapshot = Shoko::Core::Models::Session::MenuSessionSnapshot.from_state(
              duplicate_fields(
                root[:menu] || {},
                Shoko::Core::Models::Session::MenuSessionSnapshotFields
              )
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::MenuSessionSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::MenuSessionSnapshot'
            end

            @state.update(snapshot.to_state_updates)
            snapshot
          end

          def update
            raise ArgumentError, 'block required' unless block_given?

            save(yield(load))
          end

          def snapshot
            load
          end

          def search_active?
            search_active == true
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

          def current_menu_mode
            mode
          end

          def selected_library_index
            browse_selected
          end

          def selected_annotation_record
            selected_annotation
          end

          def selected_annotation_book_path
            selected_annotation_book
          end

          def annotation_editor_text
            annotation_edit_text
          end
        end
      end
    end
  end
end
