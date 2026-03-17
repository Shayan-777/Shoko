# frozen_string_literal: true

require_relative '../../../core/models/session/reader_snapshot'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative 'reader_ui_session_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader session store over ObserverStateStore.
        class ReaderSessionStoreAdapter
          include Shoko::Core::Ports::Outbound::ReaderSessionStore
          LIVE_UI_FIELDS = ReaderUiSessionRegistry::LIVE_FIELDS

          Shoko::Core::Models::Session::ReaderSnapshotFields.each do |field|
            define_method(field) do
              load.to_h[field]
            end
          end

          LIVE_UI_FIELDS.each do |field|
            define_method(field) do
              @ui_session_registry&.read(field)
            end
          end

          def initialize(state, ui_session_registry: nil)
            @state = state
            @ui_session_registry = ui_session_registry
          end

          def load
            state = @state.current_state
            Shoko::Core::Models::Session::ReaderSnapshot.from_state(
              reader_state: state[:reader],
              ui_state: state[:ui]
            )
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::ReaderSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::ReaderSnapshot'
            end

            @state.update(snapshot.to_state_updates)
            snapshot
          end

          def update
            raise ArgumentError, 'block required' unless block_given?

            save(yield(load))
          end

          def snapshot
            load
          end

          def sidebar_visible?
            load.sidebar_visible?
          end

          def loading_active?
            load.loading_active?
          end

          def running?
            load.running == true
          end

          def sidebar_toc_filter_active?
            load.sidebar_toc_filter_active == true
          end
        end
      end
    end
  end
end
