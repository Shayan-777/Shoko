# frozen_string_literal: true

require_relative '../../../application/ports/outbound/observer_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Application adapter implementing the ObserverRegistry port.
        # Delegates observer registration to ObserverStateStore.
        class ObserverRegistryAdapter
          include Application::Ports::Outbound::ObserverRegistry

          def initialize(state)
            @state = state
          end

          # @param observer [Object] Object implementing state_changed method
          # @param paths [Array<Array<Symbol>>] State paths to observe
          def add_observer(observer, *paths)
            @state.add_observer(observer, *paths)
          end

          # @param observer [Object] Observer to remove
          def remove_observer(observer)
            @state.remove_observer(observer)
          end
        end
      end
    end
  end
end
