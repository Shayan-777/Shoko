# frozen_string_literal: true

module Shoko
  module Core
    module Models
      module Session
        require_relative 'schema'

        ReaderSnapshotFields = Schema::READER_FIELDS

        # Immutable reader/session snapshot loaded from the state store.
        class ReaderSnapshot < Data.define(*ReaderSnapshotFields)
          DEFAULTS = Schema::READER_DEFAULTS

          def self.build(attributes = {})
            new(**DEFAULTS.merge(attributes))
          end

          def self.from_state(reader_state:, ui_state:)
            build(
              (reader_state || {}).merge(
                loading_active: ui_state&.dig(:loading_active) == true,
                loading_message: ui_state&.dig(:loading_message),
                loading_progress: ui_state&.dig(:loading_progress)
              )
            )
          end

          def with(**attributes)
            self.class.build(to_h.merge(attributes))
          end

          def sidebar_visible?
            sidebar_visible == true
          end

          def loading_active?
            loading_active == true
          end

          def to_state_updates
            reader_updates = to_h.each_with_object({}) do |(field, value), updates|
              next if %i[loading_active loading_message loading_progress].include?(field)

              updates[[:reader, field]] = value
            end

            reader_updates.merge(
              [:ui, :loading_active] => loading_active,
              [:ui, :loading_message] => loading_message,
              [:ui, :loading_progress] => loading_progress
            )
          end
        end
      end
    end
  end
end
