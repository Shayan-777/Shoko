# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        module Actions
          # Base action for immutable-like state updates via StateStore#dispatch
          class BaseAction
            def initialize(payload = {})
              @payload = payload
            end

            # Apply the action to the given StateStore instance
            # Implement in subclasses
            def apply(_state)
              raise NotImplementedError, 'Action subclasses must implement #apply(state)'
            end

            protected

            attr_reader :payload
          end
        end
      end
    end
  end
end
