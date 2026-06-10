# frozen_string_literal: true

module Shoko
  module Application
    module Services
      # Runs a job off the UI thread and relays its results back as small
      # apply-blocks that the UI thread executes on its next tick. This keeps
      # every state write on the UI thread (jobs only compute and enqueue),
      # which is the same discipline the pagination feedback follows.
      #
      # Without an executor the relay degrades to fully synchronous behavior:
      # the job runs inline and its results apply immediately — callers built
      # without a worker (tests, simple wiring) behave exactly like blocking
      # code did.
      class AsyncResultRelay
        def initialize(async_executor: nil, executor_factory: nil, logger: nil)
          @async_executor = async_executor
          @executor_factory = executor_factory
          @logger = logger
          @mailbox = Queue.new
          @pending_jobs = 0
          @mutex = Mutex.new
        end

        # Runs the job. The job executes off the UI thread (when an executor is
        # available) and must not touch shared state directly — it reports back
        # exclusively via #enqueue. Returns false when the job could not be
        # submitted (executor shutting down). Without an executor the job runs
        # inline and its errors propagate to the caller, exactly like the
        # blocking code this relay replaces.
        def submit(&job)
          raise ArgumentError, 'job block required' unless job

          executor = resolve_executor
          return run_inline(job) unless executor

          submit_to_executor(executor, job)
        end

        # Queues a block for execution on the UI thread's next drain.
        def enqueue(&apply_block)
          raise ArgumentError, 'apply block required' unless apply_block

          @mailbox << apply_block
        end

        # Applies all queued results on the calling (UI) thread. Returns the
        # number of applied blocks. Errors raised by an apply-block propagate
        # deliberately — they are UI-thread failures, not background noise.
        # The UI thread is the only consumer, so empty?/pop cannot race.
        def drain!
          applied = 0
          until @mailbox.empty?
            @mailbox.pop.call
            applied += 1
          end
          applied
        end

        # True while a submitted job is still running or results await drain —
        # drives "keep polling" decisions in the UI loops.
        def busy?
          @mutex.synchronize { @pending_jobs.positive? } || !@mailbox.empty?
        end

        def shutdown
          executor = @mutex.synchronize do
            value = @async_executor
            @async_executor = nil
            @executor_factory = nil
            value
          end
          executor&.shutdown
        end

        private

        # A failed submit must never break the UI path that requested it; the
        # caller sees false and its "started" status simply stays put.
        def submit_to_executor(executor, job)
          begin_job
          executor.submit do
            job.call
          ensure
            finish_job
          end
          true
        # resilient-boundary
        rescue StandardError => e
          finish_job
          swallow_submit_error(e)
          false
        end

        # A failing executor factory degrades to inline (blocking) execution
        # rather than losing the request entirely.
        def resolve_executor
          @mutex.synchronize do
            @async_executor ||= @executor_factory&.call
          end
        # resilient-boundary
        rescue StandardError => e
          swallow_submit_error(e)
          nil
        end

        def run_inline(job)
          job.call
          drain!
          true
        end

        def begin_job
          @mutex.synchronize { @pending_jobs += 1 }
        end

        def finish_job
          @mutex.synchronize { @pending_jobs -= 1 if @pending_jobs.positive? }
        end

        def swallow_submit_error(error)
          @logger&.debug(
            'async_result_relay.submit_failed',
            error: error.class.name,
            message: error.message
          )
        end
      end
    end
  end
end
