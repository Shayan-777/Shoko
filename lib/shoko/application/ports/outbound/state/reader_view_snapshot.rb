# frozen_string_literal: true

require 'shoko/application/state/snapshot_factory'
require 'shoko/application/state/schema/reader_view'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Port-contract snapshot for the reader view-state slice.
          # Data contract for `Application::Ports::Outbound::ReaderViewStateStore`.
          #
          # The loading mirror lives canonically in `state[:ui]`; the
          # adapter implementing the port is responsible for merging it on
          # read and routing writes to the right partition.
          ReaderViewSnapshot = Shoko::Application::State::SnapshotFactory.define_snapshot(
            fields: Shoko::Application::State::Schema::ReaderView::FIELDS,
            defaults: Shoko::Application::State::Schema::ReaderView::DEFAULTS,
            partition: :reader
          )

          # Override to_state_updates so loading_* writes are routed to :ui
          # rather than :reader, preserving the existing canonical-location
          # invariant.
          ReaderViewSnapshot.class_eval do
            LOADING_UPDATE_PATHS = {
              loading_active: %i[ui loading_active],
              loading_message: %i[ui loading_message],
              loading_progress: %i[ui loading_progress],
            }.freeze
            LOADING_FIELDS = Shoko::Application::State::Schema::ReaderView::LOADING_FIELDS

            def to_state_updates
              support = Shoko::Application::State::SnapshotFactory
              support
                .root_state_updates_except(self, root: :reader, skipped_fields: LOADING_FIELDS)
                .merge(
                  support.mapped_state_updates(
                    {
                      loading_active: loading_active,
                      loading_message: loading_message,
                      loading_progress: loading_progress,
                    },
                    LOADING_UPDATE_PATHS
                  )
                )
            end

            def self.from_state(reader_state:, ui_state:)
              support = Shoko::Application::State::SnapshotFactory
              build(support.merged_loading_attributes(reader_state, ui_state))
            end

            def loading_active? = loading_active == true
            def dictionary_visible? = dictionary_visible == true
          end
        end
      end
    end
  end
end
