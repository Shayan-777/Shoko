# frozen_string_literal: true

require_relative 'schema'
require_relative 'snapshot_support'

module Shoko
  module Core
    module Models
      # Split reader pagination snapshots used by focused reader state stores.
      module Session
        ReaderPaginationSnapshotFields = Schema::READER_PAGINATION_FIELDS
        READER_PAGINATION_SNAPSHOT_DEFAULTS = Schema::READER_PAGINATION_DEFAULTS.freeze

        # Immutable reader pagination snapshot.
        ReaderPaginationSnapshot = Data.define(*ReaderPaginationSnapshotFields) do
          def self.build(attributes = {})
            SnapshotSupport.build(self, READER_PAGINATION_SNAPSHOT_DEFAULTS, attributes)
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

        ReaderPaginationSnapshot::DEFAULTS = READER_PAGINATION_SNAPSHOT_DEFAULTS
      end
    end
  end
end
