# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    # Single-thread worker with monitored queue and graceful shutdown semantics.
    class BackgroundWorker
      # @param name [String] Worker thread name
      # @param logger [Core::Ports::Outbound::Logging] Logger adapter (required)
      def initialize(logger:, name: 'shoko-worker')
        @name = name
        @logger = logger
        @queue = Queue.new
        @shutdown = false
        @mutex = Mutex.new
        @thread = spawn_thread
      end

      def submit(&block)
        raise ArgumentError, 'block required' unless block

        @mutex.synchronize do
          raise WorkerStoppedError, 'worker is shutting down' if @shutdown

          @queue << block
        end
      end

      def shutdown(timeout: 2.0)
        thread = nil
        @mutex.synchronize do
          return if @shutdown

          @shutdown = true
          thread = @thread
          @queue << nil if thread&.alive?
        end
        thread&.join(timeout)
      ensure
        @thread = nil
      end

      class WorkerStoppedError < StandardError; end

      private

      def spawn_thread
        Thread.new do
          Thread.current.name = @name if Thread.current.respond_to?(:name=)
          loop do
            job = @queue.pop
            break if job.nil? && @shutdown

            next unless job

            begin
              job.call
            rescue StandardError => e
              @logger.error('Background worker job failed',
                            worker: @name,
                            error: e.message)
            end
          end
        end
      end
    end
  end
end
