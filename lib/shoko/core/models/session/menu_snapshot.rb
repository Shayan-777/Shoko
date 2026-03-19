# frozen_string_literal: true

require_relative 'schema'
require_relative 'snapshot_support'

module Shoko
  module Core
    module Models
      # Immutable session snapshots and canonical schema records.
      module Session
        MenuSnapshotFields = Schema::MENU_FIELDS
        MENU_SNAPSHOT_DEFAULTS = Schema::MENU_DEFAULTS.freeze

        # Immutable menu/session snapshot loaded from the state store.
        MenuSnapshot = Data.define(*MenuSnapshotFields) do
          def self.build(attributes = {})
            SnapshotSupport.build(self, MENU_SNAPSHOT_DEFAULTS, attributes)
          end

          def self.from_state(menu_state)
            build(menu_state || {})
          end

          def with(**attributes)
            SnapshotSupport.with(self, attributes)
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

          def dictionary_entries
            Array(dictionary_results)
          end

          def to_state_updates
            SnapshotSupport.root_state_updates(self, :menu)
          end
        end

        MenuSnapshot::DEFAULTS = MENU_SNAPSHOT_DEFAULTS
      end
    end
  end
end
