# frozen_string_literal: true

require_relative '../../../core/models/session/reader_snapshot'
require_relative '../../../core/models/session/reader_session_snapshot'
require_relative '../../../core/models/session/reader_view_state_snapshot'
require_relative '../../../core/models/session/reader_pagination_snapshot'
require_relative 'reader_ui_session_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Read-only composite reader state adapter that merges session, view, and
        # pagination projections for legacy/UI consumers that still expect the
        # broad ReaderSnapshot surface.
        class ReaderSnapshotProjectionAdapter
          LIVE_UI_FIELDS = ReaderUiSessionRegistry::LIVE_FIELDS

          Shoko::Core::Models::Session::ReaderSessionSnapshotFields.each do |field|
            define_method(field) { @reader_session_store.load.to_h.fetch(field) }
          end

          Shoko::Core::Models::Session::ReaderViewStateSnapshotFields.each do |field|
            define_method(field) { @reader_view_state_store.load.to_h.fetch(field) }
          end

          Shoko::Core::Models::Session::ReaderPaginationSnapshotFields.each do |field|
            define_method(field) { @reader_pagination_store.load.to_h.fetch(field) }
          end

          LIVE_UI_FIELDS.each do |field|
            define_method(field) do
              @ui_session_registry&.read(field)
            end
          end

          def initialize(state:, reader_session_store:, reader_view_state_store:, reader_pagination_store:,
                         ui_session_registry: nil)
            @state = state
            @reader_session_store = reader_session_store
            @reader_view_state_store = reader_view_state_store
            @reader_pagination_store = reader_pagination_store
            @ui_session_registry = ui_session_registry
            @snapshot_root = nil
            @snapshot = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            snapshot = Shoko::Core::Models::Session::ReaderSnapshot.build(
              @reader_session_store.load.to_h
                .merge(@reader_view_state_store.load.to_h)
                .merge(@reader_pagination_store.load.to_h)
            )
            @snapshot_root = root
            @snapshot = snapshot
            snapshot
          end

          def snapshot
            load
          end

          def sidebar_visible?
            @reader_view_state_store.sidebar_visible?
          end

          def loading_active?
            @reader_view_state_store.loading_active?
          end

          def running?
            @reader_session_store.running == true
          end

          def sidebar_toc_filter_active?
            @reader_view_state_store.sidebar_toc_filter_active?
          end

          def dictionary_visible?
            @reader_view_state_store.dictionary_visible?
          end
        end
      end
    end
  end
end
