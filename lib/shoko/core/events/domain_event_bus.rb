# frozen_string_literal: true

require_relative 'base_domain_event'

module Shoko
  module Core
    module Events
      # Domain event bus for publishing and subscribing to domain events.
      #
      # This provides a domain-specific event bus that depends on the EventPublisher
      # port and handles domain event serialization, routing, and subscription
      # management.
      #
      # @example Publishing an event
      #   event_bus.publish(BookmarkAdded.new(book_path: path, bookmark: bookmark))
      #
      # @example Subscribing to events
      #   event_bus.subscribe(BookmarkAdded) { |event| handle_bookmark_event(event) }
      class DomainEventBus
        def initialize(event_publisher:, logger: nil)
          @event_publisher = event_publisher
          @logger = logger
          @subscribers = Hash.new { |h, k| h[k] = [] }
          @middleware = []
        end

        # Publish a domain event
        #
        # @param event [Core::Events::BaseDomainEvent] Domain event to publish
        def publish(event)
          raise ArgumentError, 'Event must be a BaseDomainEvent' unless event.is_a?(Core::Events::BaseDomainEvent)

          # Apply middleware chain
          processed_event = apply_middleware(event)
          return if processed_event.nil? # Event was filtered out

          # Publish through abstract event publisher port
          @event_publisher.publish_event(processed_event.event_type.to_sym, event_data: processed_event.to_h)

          # Notify domain subscribers directly
          notify_subscribers(processed_event)
        end

        # Subscribe to a specific event type
        #
        # @param event_type [Class] Event class to subscribe to
        # @param handler [Proc] Handler block or callable
        # @yield [event] Block to handle the event
        def subscribe(event_type, handler = nil, &)
          handler = resolve_callable!(handler, &)
          @subscribers[event_type] << handler
        end

        # Subscribe to multiple event types with the same handler
        #
        # @param event_types [Array<Class>] Event classes to subscribe to
        # @param handler [Proc] Handler block or callable
        # @yield [event] Block to handle the event
        def subscribe_to_many(event_types, handler = nil, &)
          handler = resolve_callable!(handler, &)
          event_types.each { |type| subscribe(type, handler) }
        end

        # Unsubscribe from an event type
        #
        # @param event_type [Class] Event class to unsubscribe from
        # @param handler [Proc] Specific handler to remove (optional)
        def unsubscribe(event_type, handler = nil)
          if handler
            @subscribers[event_type].delete(handler)
          else
            @subscribers.delete(event_type)
          end
        end

        # Add middleware to the event processing pipeline
        #
        # @param middleware [Proc] Middleware that processes events
        # @yield [event] Block that processes the event and returns modified event or nil
        def add_middleware(middleware = nil, &block)
          middleware = block if block_given?
          raise ArgumentError, 'Middleware must be provided' unless middleware

          @middleware << middleware
        end

        def resolve_callable!(callable, &block)
          callable = block if block_given?
          raise ArgumentError, 'Handler must be provided' unless callable

          callable
        end

        # Get all subscribers for an event type
        #
        # @param event_type [Class] Event class
        # @return [Array<Proc>] List of subscribers
        def subscribers_for(event_type)
          @subscribers[event_type].dup
        end

        # Check if there are subscribers for an event type
        #
        # @param event_type [Class] Event class
        # @return [Boolean] True if there are subscribers
        def subscribers?(event_type)
          @subscribers[event_type].any?
        end

        # Clear all subscribers (useful for testing)
        def clear_subscribers
          @subscribers.clear
        end

        # Get subscriber count for an event type
        #
        # @param event_type [Class] Event class
        # @return [Integer] Number of subscribers
        def subscriber_count(event_type)
          @subscribers[event_type].size
        end

        # Get total number of subscribers across all event types
        #
        # @return [Integer] Total subscriber count
        def total_subscribers
          @subscribers.values.sum(&:size)
        end

        private

        def apply_middleware(event)
          @middleware.reduce(event) do |current_event, middleware|
            next current_event if current_event.nil?

            begin
              middleware.call(current_event)
            rescue StandardError => e
              @logger&.error("Domain event middleware error: #{e.message}")
              current_event
            end
          end
        end

        def notify_subscribers(event)
          event_type = event.class

          @subscribers[event_type].each do |handler|
            handler.call(event)
          rescue StandardError => e
            @logger&.error("Domain event subscriber error for #{event_type}: #{e.message}")
          end
        end
      end
    end
  end
end
