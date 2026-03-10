# frozen_string_literal: true

require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/ports/outbound/menu_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed menu session store over ObserverStateStore.
        class MenuSessionStoreAdapter
          include Shoko::Core::Ports::Outbound::MenuSessionStore

          def initialize(state)
            @state = state
          end

          def load
            state = @state.current_state
            Shoko::Core::Models::Session::MenuSnapshot.from_state(state[:menu])
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::MenuSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::MenuSnapshot'
            end

            @state.update(snapshot.to_state_updates)
            snapshot
          end
        end
      end
    end
  end
end
