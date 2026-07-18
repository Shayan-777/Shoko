# frozen_string_literal: true

require 'shoko/application/state/snapshot_factory'
require 'shoko/application/state/schema/reader_process'
require 'shoko/application/state/schema/reader_pagination'
require 'shoko/application/state/schema/reader_view'
require 'shoko/core/reading/schema'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Composite reader snapshot covering the full `state[:reader]`
          # partition: domain reading + application process + application
          # pagination + UI view-state slices.
          #
          # This is the deliberate cross-slice read model — use it when a
          # consumer needs a unified view of the whole reader partition (e.g.
          # the reader projection adapter, which merges the session + view +
          # pagination stores). Use the focused snapshots
          # (`ReaderSessionSnapshot`, `ReaderPaginationSnapshot`,
          # `ReaderViewSnapshot`) when a consumer only touches a single slice.
          # The two levels coexist by design; this is not a legacy shim.
          reader_fields = (Shoko::Core::Reading::Schema::FIELDS +
                           Shoko::Application::State::Schema::ReaderProcess::FIELDS +
                           Shoko::Application::State::Schema::ReaderPagination::FIELDS +
                           Shoko::Application::State::Schema::ReaderView::FIELDS).freeze
          reader_defaults = [
            Shoko::Core::Reading::Schema::DEFAULTS,
            Shoko::Application::State::Schema::ReaderProcess::DEFAULTS,
            Shoko::Application::State::Schema::ReaderPagination::DEFAULTS,
            Shoko::Application::State::Schema::ReaderView::DEFAULTS,
          ].reduce({}, :merge).freeze

          ReaderSnapshot = Shoko::Application::State::SnapshotFactory.define_snapshot(
            fields: reader_fields,
            defaults: reader_defaults,
            partition: :reader
          )

          ReaderSnapshot.class_eval do
            VIEW_LOADING_FIELDS = Shoko::Application::State::Schema::ReaderView::LOADING_FIELDS
            VIEW_LOADING_UPDATE_PATHS = {
              loading_active: %i[ui loading_active],
              loading_message: %i[ui loading_message],
              loading_progress: %i[ui loading_progress],
            }.freeze

            def self.from_state(reader_state:, ui_state:)
              support = Shoko::Application::State::SnapshotFactory
              build(support.merged_loading_attributes(reader_state, ui_state))
            end

            def to_state_updates
              support = Shoko::Application::State::SnapshotFactory
              support
                .root_state_updates_except(self, root: :reader, skipped_fields: VIEW_LOADING_FIELDS)
                .merge(
                  support.mapped_state_updates(
                    {
                      loading_active: loading_active,
                      loading_message: loading_message,
                      loading_progress: loading_progress,
                    },
                    VIEW_LOADING_UPDATE_PATHS
                  )
                )
            end

            def loading_active? = loading_active == true
          end
        end
      end
    end
  end
end
