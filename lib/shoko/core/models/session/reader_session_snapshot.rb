# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Split reader session snapshots used by focused reader state stores.
      module Session
        require_relative 'schema'

        ReaderSessionSnapshotFields = Schema::READER_SESSION_FIELDS

        # Immutable reader session snapshot containing navigation/progress state.
        class ReaderSessionSnapshot < Data.define(*ReaderSessionSnapshotFields)
          DEFAULTS = Schema::READER_SESSION_DEFAULTS

          def self.build(attributes = {})
            new(**DEFAULTS, **attributes)
          end

          def self.from_state(reader_state)
            build(reader_state || {})
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def to_state_updates
            to_h.transform_keys { |field| [:reader, field] }
          end
        end
      end
    end
  end
end
