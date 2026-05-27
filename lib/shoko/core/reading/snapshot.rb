# frozen_string_literal: true

require_relative 'schema'

module Shoko
  module Core
    module Reading
      # Immutable reading-domain snapshot.
      #
      # Holds only fields that describe the reader's position and marks within
      # the book. Constructed by the application's reading-domain projection;
      # may be consumed anywhere (core, application, adapters) without violating
      # layer boundaries, since reading state is the deepest contract.
      Snapshot = Data.define(*Schema::FIELDS) do
        DEFAULTS = Schema::DEFAULTS

        def self.build(attributes = {})
          new(**DEFAULTS, **attributes)
        end

        def self.from_state(reader_state)
          source = reader_state || {}
          attrs = Schema::FIELDS.each_with_object({}) do |field, acc|
            acc[field] = source.fetch(field) { DEFAULTS[field] }
          end
          new(**attrs)
        end

        def with(**attributes)
          self.class.new(**to_h, **attributes)
        end

        def to_state_updates
          to_h.transform_keys { |field| [Schema::PARTITION, field] }
        end
      end

      Snapshot::FIELDS = Schema::FIELDS
      Snapshot::DEFAULTS = Schema::DEFAULTS
    end
  end
end
