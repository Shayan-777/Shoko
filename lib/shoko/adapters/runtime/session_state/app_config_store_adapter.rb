# frozen_string_literal: true

require_relative '../../../core/models/session/config_snapshot'
require_relative '../../../core/ports/outbound/app_config_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-backed application config store over ObserverStateStore.
        class AppConfigStoreAdapter
          include Shoko::Core::Ports::Outbound::AppConfigStore

          def initialize(state)
            @state = state
          end

          def load
            state = @state.current_state
            Shoko::Core::Models::Session::ConfigSnapshot.from_state(state[:config])
          end

          def save(snapshot)
            unless snapshot.is_a?(Shoko::Core::Models::Session::ConfigSnapshot)
              raise ArgumentError, 'snapshot must be Core::Models::Session::ConfigSnapshot'
            end

            @state.update(snapshot.to_state_updates)
            @state.save_config
            snapshot
          end
        end
      end
    end
  end
end
