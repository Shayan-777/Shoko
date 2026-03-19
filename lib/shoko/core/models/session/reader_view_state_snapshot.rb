# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Split reader view-state snapshots used by focused reader state stores.
      module Session
        require_relative 'schema'

        ReaderViewStateSnapshotFields = Schema::READER_VIEW_STATE_FIELDS
        READER_VIEW_STATE_LOADING_FIELDS = %i[
          loading_active
          loading_message
          loading_progress
        ].freeze

        # Immutable reader UI/view-state snapshot.
        class ReaderViewStateSnapshot < Data.define(*ReaderViewStateSnapshotFields)
          DEFAULTS = Schema::READER_VIEW_STATE_DEFAULTS

          def self.build(attributes = {})
            new(**DEFAULTS, **attributes)
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

          def dictionary_visible?
            dictionary_visible == true
          end

          def to_state_updates
            reader_updates = to_h.each_with_object({}) do |(field, value), updates|
              next if READER_VIEW_STATE_LOADING_FIELDS.include?(field)

              updates[[:reader, field]] = value
            end

            reader_updates.merge(
              %i[ui loading_active] => loading_active,
              %i[ui loading_message] => loading_message,
              %i[ui loading_progress] => loading_progress
            )
          end
        end
      end
    end
  end
end
