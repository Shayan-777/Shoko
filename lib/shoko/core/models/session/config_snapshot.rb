# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        require_relative 'schema'

        ConfigSnapshotFields = Schema::CONFIG_FIELDS

        # Immutable application configuration snapshot.
        class ConfigSnapshot < Data.define(*ConfigSnapshotFields)
          SCHEMA_VERSION = Schema::CONFIG_SCHEMA_VERSION
          DEFAULTS = Schema::CONFIG_DEFAULTS

          def self.build(attributes = {})
            new(**DEFAULTS.merge(attributes))
          end

          def self.from_state(config_state)
            build(config_state || {})
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def to_state_updates
            to_h.each_with_object({}) do |(field, value), updates|
              updates[[:config, field]] = value
            end
          end
        end
      end
    end
  end
end
