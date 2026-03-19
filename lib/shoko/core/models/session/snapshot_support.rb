# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Shared helpers for immutable session snapshot classes.
      module Session
        # Shared constructors and state-projection helpers for session snapshots.
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
        end
      end
    end
  end
end
