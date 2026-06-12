# frozen_string_literal: true

require 'shoko/application/ports/outbound/state/reader_snapshot'
require 'shoko/application/ports/outbound/state/reader_session_snapshot'
require 'shoko/application/ports/outbound/state/reader_view_snapshot'
require 'shoko/application/ports/outbound/state/reader_pagination_snapshot'
require_relative '../../ui/state/reader_component_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Read-only composite reader state adapter that merges session, view, and
        # pagination projections for consumers that still expect the broad
        # ReaderSnapshot surface. Live UI component refs flow through the
        # `Adapters::Ui::State::ReaderComponentRegistry` rather than the snapshot.
        class ReaderSnapshotProjectionAdapter
          LIVE_UI_FIELDS = Shoko::Adapters::Ui::State::ReaderComponentRegistry::LIVE_FIELDS

          Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot::FIELDS.each do |field|
            define_method(field) { @reader_session_store.load.to_h.fetch(field) }
          end

          Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot::FIELDS.each do |field|
            define_method(field) { @reader_view_state_store.load.to_h.fetch(field) }
          end

          Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot::FIELDS.each do |field|
            define_method(field) { @reader_pagination_store.load.to_h.fetch(field) }
          end

          LIVE_UI_FIELDS.each do |field|
            define_method(field) do
              @component_registry&.read(field)
            end
          end

          def initialize(state:, reader_session_store:, reader_view_state_store:, reader_pagination_store:,
                         component_registry: nil)
            @state = state
            @reader_session_store = reader_session_store
            @reader_view_state_store = reader_view_state_store
            @reader_pagination_store = reader_pagination_store
            @component_registry = component_registry
            @snapshot_root = nil
            @snapshot = nil
          end

          def load
            root = @state.peek
            return @snapshot if @snapshot_root.equal?(root) && @snapshot

            snapshot = Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
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

          def loading_active?
            @reader_view_state_store.loading_active?
          end

          def running?
            @reader_session_store.running == true
          end

          def dictionary_visible?
            @reader_view_state_store.dictionary_visible?
          end
        end
      end
    end
  end
end
