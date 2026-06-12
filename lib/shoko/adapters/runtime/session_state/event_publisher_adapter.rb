# frozen_string_literal: true

require 'shoko/application/ports/outbound/event_publisher'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter that bridges the EventPublisher port to the session-state event bus.
        class EventPublisherAdapter
          include Shoko::Application::Ports::Outbound::EventPublisher

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
end
