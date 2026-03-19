# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Split menu transient snapshots used by focused menu state stores.
      module Session
        require_relative 'schema'

        MenuTransientSnapshotFields = Schema::MENU_TRANSIENT_FIELDS

        # Immutable menu transient snapshot containing workflow/render payloads.
        class MenuTransientSnapshot < Data.define(*MenuTransientSnapshotFields)
          DEFAULTS = Schema::MENU_TRANSIENT_DEFAULTS

          def self.build(attributes = {})
            new(**DEFAULTS.merge(attributes))
          end

          def self.from_state(menu_state)
            build(menu_state || {})
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def loading_active?
            loading_active == true
          end

          def dictionary_entries
            Array(dictionary_results)
          end

          def to_state_updates
            to_h.transform_keys { |field| [:menu, field] }
          end
        end
      end
    end
  end
end
