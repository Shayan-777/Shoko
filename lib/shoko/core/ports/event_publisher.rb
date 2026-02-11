# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port for publishing infrastructure-compatible events from domain/application bridges.
      module EventPublisher
        # @param event_type [Symbol]
        # @param event_data [Hash]
        def publish_event(event_type, event_data = {})
          raise NotImplementedError, "#{self.class} must implement #publish_event"
        end
      end
    end
  end
end
