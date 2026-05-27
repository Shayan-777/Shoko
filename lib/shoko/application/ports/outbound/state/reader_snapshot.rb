# frozen_string_literal: true

require_relative '../../../state/snapshot_support'
require_relative '../../../state/schema/reader_process'
require_relative '../../../state/schema/reader_pagination'
require_relative '../../../state/schema/reader_view'
require_relative '../../../../core/reading/schema'

module Shoko
  module Application
    module Ports
      module Outbound
        module State
          # Composite reader snapshot covering the full `state[:reader]`
          # partition: domain reading + application process + application
          # pagination + UI view-state slices.
          #
          # Returned by the reader projection adapter as a convenience for
          # consumers that need a single object exposing every reader field.
          # New code should prefer the focused snapshots
          # (`ReaderSessionSnapshot`, `ReaderPaginationSnapshot`,
          # `ReaderViewSnapshot`) — the composite is preserved for existing
          # call sites that read across slices.
          module ReaderSnapshotInternal
            CORE_FIELDS = Shoko::Core::Reading::Schema::FIELDS
            PROCESS_FIELDS = Shoko::Application::State::Schema::ReaderProcess::FIELDS
            PAGINATION_FIELDS = Shoko::Application::State::Schema::ReaderPagination::FIELDS
            VIEW_FIELDS = Shoko::Application::State::Schema::ReaderView::FIELDS

            FIELDS = (CORE_FIELDS + PROCESS_FIELDS + PAGINATION_FIELDS + VIEW_FIELDS).freeze
            DEFAULTS = [
              Shoko::Core::Reading::Schema::DEFAULTS,
              Shoko::Application::State::Schema::ReaderProcess::DEFAULTS,
              Shoko::Application::State::Schema::ReaderPagination::DEFAULTS,
              Shoko::Application::State::Schema::ReaderView::DEFAULTS,
            ].reduce({}, :merge).freeze
          end
          private_constant :ReaderSnapshotInternal

          ReaderSnapshot = Shoko::Application::State::SnapshotSupport.define_snapshot(
            fields: ReaderSnapshotInternal::FIELDS,
            defaults: ReaderSnapshotInternal::DEFAULTS,
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
              support = Shoko::Application::State::SnapshotSupport
              build(support.merged_loading_attributes(reader_state, ui_state))
            end

            def to_state_updates
              support = Shoko::Application::State::SnapshotSupport
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

            def sidebar_visible? = sidebar_visible == true
            def loading_active? = loading_active == true
          end
        end
      end
    end
  end
end
