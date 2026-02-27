# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for managing state observer registrations.
        # Adapters implementing this interface allow components to subscribe
        # to state change notifications without coupling to the state store.
        module ObserverRegistry
          # Register an observer for specific state paths.
          # Observer should respond to `state_changed(path, old_value, new_value)`.
          #
          # @param observer [Object] Object implementing state_changed method
          # @param paths [Array<Array<Symbol>>] State paths to observe
          # @return [void]
          def add_observer(observer, *paths)
            raise NotImplementedError, "#{self.class} must implement #add_observer"
          end

          # Remove observer from all paths.
          #
          # @param observer [Object] Observer to remove
          # @return [void]
          def remove_observer(observer)
            raise NotImplementedError, "#{self.class} must implement #remove_observer"
          end
        end
      end
    end
  end
end
