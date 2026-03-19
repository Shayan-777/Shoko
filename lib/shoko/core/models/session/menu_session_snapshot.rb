# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Split menu session snapshots used by focused menu state stores.
      module Session
        require_relative 'schema'

        MenuSessionSnapshotFields = Schema::MENU_SESSION_FIELDS

        # Immutable menu session snapshot containing durable menu state.
        class MenuSessionSnapshot < Data.define(*MenuSessionSnapshotFields)
          DEFAULTS = Schema::MENU_SESSION_DEFAULTS

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

          def to_state_updates
            to_h.transform_keys { |field| [:menu, field] }
          end
        end
      end
    end
  end
end
