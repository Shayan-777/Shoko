# frozen_string_literal: true

module Shoko
  module Application
    module State
      # Thread-safe event bus for application-wide event handling.
      # Complements `ObserverStateStore` by broadcasting application events
      # to subscribers that don't observe individual state paths.
      class EventBus
        # @param logger [Application::Ports::Outbound::Logging] Logger adapter (required)
        def initialize(logger:)
          @subscribers = Hash.new { |h, k| h[k] = [] }
          @mutex = Mutex.new
          @logger = logger
        end

        # Subscribe to specific event types
        #
        # @param subscriber [Object] Object responding to #handle_event(event)
        # @param *event_types [Array<Symbol>] Event types to subscribe to
        def subscribe(subscriber, *event_types)
          @mutex.synchronize do
            event_types.each do |event_type|
              list = @subscribers[event_type]
              list << subscriber unless list.include?(subscriber)
            end
          end
        end

        # Unsubscribe from all events
        #
        # @param subscriber [Object] Subscriber to remove
        def unsubscribe(subscriber)
          @mutex.synchronize do
            @subscribers.each_value { |list| list.delete(subscriber) }
          end
        end

        # Emit an event to all subscribers
        #
        # @param event [Event] Event to emit
        def emit(event)
          subscribers = @mutex.synchronize { @subscribers[event.type].dup }

          subscribers.each do |subscriber|
            safely_notify(subscriber, event)
          end
        end

        # Create and emit an event
        #
        # @param type [Symbol] Event type
        # @param data [Hash] Event data
        def emit_event(type, data = {})
          event = Event.new(type: type, data: data)
          emit(event)
        end

        private

        # Subscriber dispatch is an isolation boundary: the bus runs code it
        # does not own, so one failing subscriber must not break the emitter
        # or starve the remaining subscribers. Errors are recorded and dropped.
        def safely_notify(subscriber, event)
          subscriber.handle_event(event)
        # resilient-boundary
        rescue StandardError => e
          record_subscriber_error(subscriber, event, e)
        end

        def record_subscriber_error(subscriber, event, error)
          @logger.error(
            'Event subscriber error',
            subscriber: subscriber.class.name,
            event_type: event.type,
            error_class: error.class.name,
            error: error.message
          )
        end
      end

      # Immutable event object. (No timestamp field: it was written via
      # `Time.now` but read nowhere — a dead field plus an application-layer
      # clock bypass. If event timestamps become a real requirement, add them
      # deliberately with the injected `WallClock` port, the way the core
      # `DomainEventBus`/`EventFactory` already do. See audit ARCH-7.)
      Event = Struct.new(:type, :data) do
        def initialize(**args)
          super
          freeze
        end
      end
    end
  end
end
