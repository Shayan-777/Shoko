# frozen_string_literal: true

module Shoko
  module Application
    module State
      # Shared constructors and state-projection helpers for layered session snapshots.
      #
      # Lives in the application layer because the helpers encode awareness of the
      # state store's top-level partition keys (`:reader`, `:menu`, `:config`, `:ui`)
      # and the loading-mirror convention. Snapshot types defined in
      # `Application::Ports::Outbound::State` consume these helpers.
      module SnapshotSupport
        module_function

        def build(klass, defaults, attributes = {})
          klass.new(**defaults, **attributes)
        end

        def with(snapshot, attributes)
          build(snapshot.class, snapshot.to_h, attributes)
        end

        def root_state_updates(snapshot, root)
          snapshot.to_h.transform_keys { |field| [root, field] }
        end

        def root_state_updates_except(snapshot, root:, skipped_fields:)
          snapshot.to_h.each_with_object({}) do |(field, value), updates|
            next if skipped_fields.include?(field)

            updates[[root, field]] = value
          end
        end

        def merged_loading_attributes(state_attributes, ui_state)
          (state_attributes || {}).merge(
            loading_active: ui_state&.dig(:loading_active) == true,
            loading_message: ui_state&.dig(:loading_message),
            loading_progress: ui_state&.dig(:loading_progress)
          )
        end

        def mapped_state_updates(values, field_paths)
          field_paths.each_with_object({}) do |(field, path), updates|
            updates[path] = values.fetch(field)
          end
        end

        # Defines a state snapshot Data class with the standard
        # build/from_state/with/to_state_updates surface used across the
        # layered state contracts.
        #
        # @param fields [Array<Symbol>] field names
        # @param defaults [Hash] default values keyed by field
        # @param partition [Symbol] top-level state partition (`:reader`,
        #   `:menu`, `:config`, `:ui`) this snapshot's updates flow into
        # @return [Class] a Data subclass with the snapshot surface installed
        def define_snapshot(fields:, defaults:, partition:)
          frozen_fields = fields.dup.freeze
          frozen_defaults = defaults.dup.freeze
          klass = Data.define(*frozen_fields)
          klass.const_set(:FIELDS, frozen_fields)
          klass.const_set(:DEFAULTS, frozen_defaults)
          klass.const_set(:PARTITION, partition)
          install_snapshot_surface(klass, partition: partition)
          klass
        end

        def install_snapshot_surface(klass, partition:)
          klass.define_singleton_method(:build) do |attributes = {}|
            SnapshotSupport.build(klass, klass::DEFAULTS, attributes)
          end
          klass.define_singleton_method(:from_state) do |state|
            klass.build(state || {})
          end
          klass.define_method(:with) do |**attributes|
            SnapshotSupport.with(self, attributes)
          end
          klass.define_method(:to_state_updates) do
            SnapshotSupport.root_state_updates(self, partition)
          end
        end
      end
    end
  end
end
