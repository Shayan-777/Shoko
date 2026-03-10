# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      # Typed intent binding used by the keyboard dispatcher.
      class IntentBinding
        SKIP = Object.new.freeze

        def self.skip
          SKIP
        end

        def initialize(intent, payload: nil, &payload_builder)
          raise ArgumentError, 'intent must be a Symbol' unless intent.is_a?(Symbol)

          @intent = intent
          @payload = payload
          @payload_builder = payload_builder
        end

        def dispatch(intent_dispatcher, key)
          payload = @payload_builder ? @payload_builder.call(key) : @payload
          return :pass if payload.equal?(SKIP)

          intent_dispatcher.call(@intent, payload)
        end
      end

      # Deferred semantic binding used when the concrete intent depends on runtime state.
      class DynamicIntentBinding
        def initialize(&resolver)
          raise ArgumentError, 'resolver block is required' unless resolver

          @resolver = resolver
        end

        def dispatch(intent_dispatcher, key)
          binding = @resolver.call(key)
          return :pass if binding.nil?
          return binding.dispatch(intent_dispatcher, key) if binding.respond_to?(:dispatch)

          raise ArgumentError, "dynamic binding resolver must return a dispatchable binding, got #{binding.class}"
        end
      end

      # Adapter-local binding that should not cross the application boundary.
      class LocalBinding
        def initialize(&handler)
          raise ArgumentError, 'handler block is required' unless handler

          @handler = handler
        end

        def dispatch(_intent_dispatcher, key)
          @handler.arity.zero? ? @handler.call : @handler.call(key)
        end
      end
    end
  end
end
