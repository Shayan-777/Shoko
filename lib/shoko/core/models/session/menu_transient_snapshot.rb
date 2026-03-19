# frozen_string_literal: true

require_relative 'schema'
require_relative 'snapshot_support'

module Shoko
  module Core
    module Models
      # Split menu transient snapshots used by focused menu state stores.
      module Session
        MenuTransientSnapshotFields = Schema::MENU_TRANSIENT_FIELDS
        MENU_TRANSIENT_SNAPSHOT_DEFAULTS = Schema::MENU_TRANSIENT_DEFAULTS.freeze

        # Immutable menu transient snapshot containing workflow/render payloads.
        MenuTransientSnapshot = Data.define(*MenuTransientSnapshotFields) do
          def self.build(attributes = {})
            SnapshotSupport.build(self, MENU_TRANSIENT_SNAPSHOT_DEFAULTS, attributes)
          end

          def self.from_state(menu_state)
            build(menu_state || {})
          end

          def with(**attributes)
            SnapshotSupport.with(self, attributes)
          end

          def loading_active?
            loading_active == true
          end

          def dictionary_entries
            Array(dictionary_results)
          end

          def to_state_updates
            SnapshotSupport.root_state_updates(self, :menu)
          end
        end

        MenuTransientSnapshot::DEFAULTS = MENU_TRANSIENT_SNAPSHOT_DEFAULTS
      end
    end
  end
end
