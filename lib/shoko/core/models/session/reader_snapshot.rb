# frozen_string_literal: true

require_relative 'schema'
require_relative 'snapshot_support'

module Shoko
  module Core
    module Models
      # Immutable session snapshots and canonical schema records.
      module Session
        ReaderSnapshotFields = Schema::READER_FIELDS
        READER_SNAPSHOT_DEFAULTS = Schema::READER_DEFAULTS.freeze
        READER_LOADING_UPDATE_PATHS = {
          loading_active: %i[ui loading_active],
          loading_message: %i[ui loading_message],
          loading_progress: %i[ui loading_progress],
        }.freeze

        # Immutable reader/session snapshot loaded from the state store.
        ReaderSnapshot = Data.define(*ReaderSnapshotFields) do
          def self.build(attributes = {})
            SnapshotSupport.build(self, READER_SNAPSHOT_DEFAULTS, attributes)
          end

          def self.from_state(reader_state:, ui_state:)
            build(SnapshotSupport.merged_loading_attributes(reader_state, ui_state))
          end

          def with(**attributes)
            SnapshotSupport.with(self, attributes)
          end

          def sidebar_visible?
            sidebar_visible == true
          end

          def loading_active?
            loading_active == true
          end

          def to_state_updates
            SnapshotSupport.root_state_updates_except(
              self,
              root: :reader,
              skipped_fields: Schema::UI_BACKED_READER_FIELDS
            ).merge(
              SnapshotSupport.mapped_state_updates(
                {
                  loading_active: loading_active,
                  loading_message: loading_message,
                  loading_progress: loading_progress,
                },
                READER_LOADING_UPDATE_PATHS
              )
            )
          end
        end

        ReaderSnapshot::DEFAULTS = READER_SNAPSHOT_DEFAULTS
      end
    end
  end
end
