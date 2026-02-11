# frozen_string_literal: true

module Shoko
  module Adapters::State
    # Thread-safe event bus for application-wide event handling.
    # Complements ObserverStateStore by broadcasting application events.
    class EventBus
      # @param logger [Core::Ports::Logging] Logger adapter (required)
      # @param raise_subscriber_errors [Boolean] Re-raise subscriber errors after logging
      def initialize(logger:, raise_subscriber_errors: false)
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
        @logger = logger
        @raise_subscriber_errors = !!raise_subscriber_errors
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
        event = Event.new(type: type, data: data, timestamp: Time.now)
        emit(event)
      end

      private

      def safely_notify(subscriber, event)
        subscriber.handle_event(event)
      rescue StandardError => e
        @logger.error(
          'Event subscriber error',
          subscriber: subscriber.class.name,
          event_type: event.type,
          error: e.message
        )
        raise e if @raise_subscriber_errors
      end
    end

    # Immutable event object
    Event = Struct.new(:type, :data, :timestamp, keyword_init: true) do
      def initialize(**args)
        super
        freeze
      end
    end
  end
end
