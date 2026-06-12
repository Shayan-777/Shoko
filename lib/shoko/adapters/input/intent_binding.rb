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
    end
  end
end
