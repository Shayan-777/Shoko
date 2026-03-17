# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        require_relative 'schema'

        MenuSnapshotFields = Schema::MENU_FIELDS

        # Immutable menu/session snapshot loaded from the state store.
        class MenuSnapshot < Data.define(*MenuSnapshotFields)
          DEFAULTS = Schema::MENU_DEFAULTS

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
