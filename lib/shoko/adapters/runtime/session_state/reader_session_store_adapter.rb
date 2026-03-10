# frozen_string_literal: true

require_relative '../../../core/models/session/reader_snapshot'
require_relative '../../../core/ports/outbound/reader_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed reader session store over ObserverStateStore.
        class ReaderSessionStoreAdapter
          include Shoko::Core::Ports::Outbound::ReaderSessionStore

          def initialize(state)
            @state = state
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
        end
      end
    end
  end
end
