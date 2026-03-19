# frozen_string_literal: true

require_relative 'schema'
require_relative 'snapshot_support'

module Shoko
  module Core
    module Models
      # Immutable session snapshots and canonical schema records.
      module Session
        ConfigSnapshotFields = Schema::CONFIG_FIELDS
        CONFIG_SNAPSHOT_DEFAULTS = Schema::CONFIG_DEFAULTS.freeze

        # Immutable application configuration snapshot.
        ConfigSnapshot = Data.define(*ConfigSnapshotFields) do
          def self.build(attributes = {})
            SnapshotSupport.build(self, CONFIG_SNAPSHOT_DEFAULTS, attributes)
          end

          def self.from_state(config_state)
            build(config_state || {})
          end

          def with(**attributes)
            SnapshotSupport.with(self, attributes)
          end

          def to_state_updates
            SnapshotSupport.root_state_updates(self, :config)
          end
        end

        ConfigSnapshot::SCHEMA_VERSION = Schema::CONFIG_SCHEMA_VERSION
        ConfigSnapshot::DEFAULTS = CONFIG_SNAPSHOT_DEFAULTS
      end
    end
  end
end
