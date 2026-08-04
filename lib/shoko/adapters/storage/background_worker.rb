# frozen_string_literal: true

require 'English'
require_relative '../../application/ports/outbound/async_executor'

module Shoko
  module Adapters
    module Storage
      # Single-thread worker with monitored queue and graceful shutdown semantics.
      class BackgroundWorker
        include Shoko::Application::Ports::Outbound::AsyncExecutor

        # @param name [String] Worker thread name
        # @param logger [Application::Ports::Outbound::Logging] Logger adapter (required)
        def initialize(logger:, name: 'shoko-worker')
          @name = name
          @logger = logger
          @queue = Queue.new
          @shutdown = false
          @shutdown_signal_sent = false
          @mutex = Mutex.new
          @thread = spawn_thread
        end

        def submit(&block)
          raise ArgumentError, 'block required' unless block

          @mutex.synchronize do
            raise WorkerStoppedError, 'worker is shutting down' if @shutdown

            ensure_live_thread!
            @queue << block
          end
        end

        def shutdown(timeout: 2.0)
          thread = begin_shutdown
          return unless thread

          wait_for_shutdown(thread, timeout)
          @mutex.synchronize { @thread = nil if @thread.equal?(thread) }
          nil
        end

        def begin_shutdown
          @mutex.synchronize do
            @shutdown = true
            if @thread&.alive? && !@shutdown_signal_sent
              @queue << nil
              @shutdown_signal_sent = true
            end
            @thread
          end
        end
        private :begin_shutdown

        def wait_for_shutdown(thread, timeout)
          joined = thread.join(timeout)
          return if joined

          raise ShutdownTimeoutError,
                "worker #{@name.inspect} did not stop within #{timeout.inspect} seconds"
        end
        private :wait_for_shutdown

        class WorkerStoppedError < StandardError; end
        class ShutdownTimeoutError < StandardError; end

        private

        def ensure_live_thread!
          return if @thread&.alive?

          log_warn('Background worker thread was not alive; restarting', worker: @name)
          @thread = spawn_thread
        end

        def spawn_thread
          Thread.new do
            configure_thread
            begin
              run_worker_loop
            ensure
              log_thread_exit($ERROR_INFO)
            end
          end
        end

        def configure_thread
          Thread.current.name = @name
          Thread.current.report_on_exception = false
        end

        def run_worker_loop
          loop do
            job = @queue.pop
            break if job.nil? && @shutdown

            execute_job(job) if job
          end
        end

        # Job execution is an isolation boundary: jobs are arbitrary submitted
        # code, so a failing job must not kill the worker thread or the jobs
        # queued behind it.
        def execute_job(job)
          job.call
        # resilient-boundary
        rescue StandardError => e
          record_job_error(e)
        end

        def record_job_error(error)
          log_error(
            'Background worker job failed',
            worker: @name,
            error_class: error.class.name,
            error: error.message
          )
        end

        def log_thread_exit(exception)
          if exception
            log_error(
              'Background worker thread terminated unexpectedly',
              worker: @name,
              error_class: exception.class.name,
              error: exception.message
            )
            return
          end

          log_info('Background worker thread exited', worker: @name, reason: @shutdown ? 'shutdown' : 'stopped')
        end

        def log_error(message, **metadata)
          @logger&.error(message, **metadata)
        end

        def log_warn(message, **metadata)
          @logger&.warn(message, **metadata)
        end

        def log_info(message, **metadata)
          @logger&.info(message, **metadata)
        end
      end
    end
  end
end
