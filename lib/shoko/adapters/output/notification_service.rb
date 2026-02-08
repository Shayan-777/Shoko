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

      # Show a transient message and clear it after duration seconds.
      # @param text [String]
      # @param duration [Numeric]
      def set_message(text, duration = 2)
        @notification_writer&.show_message(text)

        duration_seconds = duration ? duration.to_f : 0.0
        if duration_seconds <= 0
          @notification_writer&.clear_message
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
      def tick
        should_clear = false

        @mutex.synchronize do
          if @clear_deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @clear_deadline
            @clear_deadline = nil
            should_clear = true
          end
        end

        return unless should_clear

        @notification_writer&.clear_message
      end
    end
  end
end
