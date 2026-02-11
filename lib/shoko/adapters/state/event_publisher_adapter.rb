# frozen_string_literal: true

require_relative '../../core/ports/event_publisher'

module Shoko
  module Adapters
    module State
      # Adapter that bridges the EventPublisher port to the legacy EventBus shape.
      class EventPublisherAdapter
        include Shoko::Core::Ports::EventPublisher

        def initialize(event_bus:)
          @event_bus = event_bus
        end

        def publish_event(event_type, event_data = {})
          @event_bus.emit_event(event_type, event_data)
        end
      end
    end
  end
end
