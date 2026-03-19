# frozen_string_literal: true

require_relative 'schema'
require_relative 'snapshot_support'

module Shoko
  module Core
    module Models
      # Split reader session snapshots used by focused reader state stores.
      module Session
        ReaderSessionSnapshotFields = Schema::READER_SESSION_FIELDS
        READER_SESSION_SNAPSHOT_DEFAULTS = Schema::READER_SESSION_DEFAULTS.freeze

        # Immutable reader session snapshot containing navigation/progress state.
        ReaderSessionSnapshot = Data.define(*ReaderSessionSnapshotFields) do
          def self.build(attributes = {})
            SnapshotSupport.build(self, READER_SESSION_SNAPSHOT_DEFAULTS, attributes)
          end

          def self.from_state(reader_state)
            build(reader_state || {})
          end

          def with(**attributes)
            SnapshotSupport.with(self, attributes)
          end

          def to_state_updates
            SnapshotSupport.root_state_updates(self, :reader)
          end
        end

        ReaderSessionSnapshot::DEFAULTS = READER_SESSION_SNAPSHOT_DEFAULTS
      end
    end
  end
end
