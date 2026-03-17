# frozen_string_literal: true

require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed menu session store over ObserverStateStore.
        class MenuSessionStoreAdapter
          include Shoko::Core::Ports::Outbound::MenuSessionStore

          Shoko::Core::Models::Session::MenuSnapshotFields.each do |field|
            define_method(field) do
              load.to_h[field]
            end
          end

          def initialize(state)
            @state = state
          end

          def load
            state = @state.current_state
            Shoko::Core::Models::Session::MenuSnapshot.from_state(state[:menu])
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::MenuSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::MenuSnapshot'
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
            load.mode
          end

          def selected_library_index
            load.browse_selected
          end

          def selected_annotation_record
            load.selected_annotation
          end

          def selected_annotation_book_path
            load.selected_annotation_book
          end

          def annotation_editor_text
            load.annotation_edit_text
          end

          def dictionary_entries
            Array(load.dictionary_results)
          end
        end
      end
    end
  end
end
