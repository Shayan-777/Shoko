# frozen_string_literal: true

require_relative '../base_adapter'

module Shoko
  module Adapters::Output
    # Centralizes ephemeral UI notifications (messages with auto-clear timers)
    class NotificationService < Shoko::Adapters::BaseAdapter
      def initialize(logger: nil, notification_writer: nil)
        super(logger: logger)
        @notification_writer = notification_writer
        @mutex = Mutex.new
        @clear_deadline = nil
      end

      # Set the notification writer if not provided at initialization
      # @param writer [Core::Ports::NotificationWriter]
      attr_writer :notification_writer

      # Show a transient message and clear it after duration seconds
      # @param state [Object] State object (deprecated, kept for compatibility)
      # @param text [String]
      # @param duration [Numeric]
      def set_message(state, text, duration = 2)
        writer = resolve_writer(state)
        writer&.show_message(text)

        duration_seconds = duration ? duration.to_f : 0.0
        if duration_seconds <= 0
          writer&.clear_message
          @mutex.synchronize { @clear_deadline = nil }
          return
        end

        cutoff = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration_seconds

        @mutex.synchronize do
          @clear_deadline = cutoff
        end
      end

      # Clear the active message when the deadline has elapsed.
      # Call on each render tick to avoid background threads.
      def tick(state)
        should_clear = false

        @mutex.synchronize do
          if @clear_deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @clear_deadline
            @clear_deadline = nil
            should_clear = true
          end
        end

        return unless should_clear

        writer = resolve_writer(state)
        writer&.clear_message
      end

      private

      def resolve_writer(state)
        return @notification_writer if @notification_writer

        # Try to resolve from state if it has dependency resolution capability
        @notification_writer = state.resolve(:notification_writer) if state.respond_to?(:resolve)
        @notification_writer
      rescue StandardError
        nil
      end
    end
  end
end
