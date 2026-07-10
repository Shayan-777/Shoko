# frozen_string_literal: true

require 'json'
require 'rbconfig'
require_relative '../../application/ports/outbound/prepagination_batch_runner'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Runtime
      # Runs the library pre-pagination batch in a separate OS process so the
      # CPU-bound page-map builds never hold this process's GIL. The child is
      # `bin/shoko --prepaginate-batch WxH`; it streams JSON-line progress on
      # stdout, which this adapter parses and forwards to the caller.
      #
      # The caller invokes #run_batch from a background worker thread, where
      # the blocking pipe reads release the GIL and cost nothing. #cancel_batch
      # may be called from any thread: it terminates the child and latches, so
      # runs are refused until #reset_cancellation re-arms the runner (the
      # port documents this pairing).
      class PrepaginationBatchProcessAdapter
        include Shoko::Application::Ports::Outbound::PrepaginationBatchRunner

        DEFAULT_SHOKO_BIN = File.expand_path('../../../../bin/shoko', __dir__)
        # Grace period between the abnormal-path TERM and the KILL escalation.
        KILL_ESCALATION_SECONDS = 2.0
        REAP_POLL_INTERVAL_SECONDS = 0.05

        def initialize(logger: nil, shoko_bin: DEFAULT_SHOKO_BIN, ruby_bin: RbConfig.ruby)
          @logger = logger
          @shoko_bin = shoko_bin
          @ruby_bin = ruby_bin
          @mutex = Mutex.new
          @pid = nil
          @cancelled = false
        end

        def run_batch(width:, height:, on_event:)
          reader = spawn_child(width, height)
          forward_events(reader, on_event) if reader
          finish_child
        # resilient-boundary
        rescue StandardError => e
          record_batch_error(e)
          abort_run
          :failed
        end

        # Latches until #reset_cancellation (see the port contract): a spawn
        # racing the cancel is killed in register_child, and later runs are
        # refused until the supervisor deliberately starts a new session.
        def cancel_batch
          pid = @mutex.synchronize do
            @cancelled = true
            @pid
          end
          terminate(pid) if pid
        end

        def reset_cancellation
          @mutex.synchronize { @cancelled = false }
        end

        private

        # Spawn failures (missing interpreter, fork limits) propagate to the
        # run_batch boundary; only the pipe ends are cleaned up here.
        def spawn_child(width, height)
          reader, writer = IO.pipe
          begin
            pid = Process.spawn(
              @ruby_bin, @shoko_bin, '--prepaginate-batch', "#{width.to_i}x#{height.to_i}",
              in: File::NULL, out: writer, err: File::NULL, pgroup: true
            )
          rescue SystemCallError
            reader.close
            writer.close
            raise
          end
          writer.close
          register_child(pid, reader)
        end

        # Refuses to keep a child spawned after a cancel that raced the spawn.
        def register_child(pid, reader)
          cancelled = @mutex.synchronize do
            @pid = pid unless @cancelled
            @cancelled
          end
          if cancelled
            terminate(pid)
            await_exit(pid)
            reader.close
            return nil
          end
          reader
        end

        def forward_events(reader, on_event)
          reader.each_line do |line|
            event = parse_event(line)
            on_event.call(event) if event
          end
        ensure
          reader.close unless reader.closed?
        end

        def parse_event(line)
          payload = JSON.parse(line)
          Shoko::Shared::HashNormalizer.symbolize_keys(payload) if payload.is_a?(Hash)
        rescue JSON::ParserError => e
          record_malformed_line(e)
        end

        def record_malformed_line(error)
          @logger&.debug('prepagination_batch_process.malformed_progress_line',
                         error: error.class.name, message: error.message)
        end

        def finish_child
          pid, cancelled = @mutex.synchronize { [@pid, @cancelled] }
          outcome = pid ? reap_outcome(pid) : :failed
          @mutex.synchronize { @pid = nil }
          cancelled ? :cancelled : outcome
        end

        def reap_outcome(pid)
          _, status = Process.wait2(pid)
          status.success? ? :completed : :failed
        rescue Errno::ECHILD => e
          # Nothing left to reap: the exit status is unobservable, and an
          # unverifiable batch must count as failed so the size signature is
          # not persisted on guesswork.
          record_batch_error(e)
          :failed
        end

        def await_exit(pid)
          Process.wait2(pid)
        rescue Errno::ECHILD => e
          record_batch_error(e)
        end

        # Abnormal exit from run_batch (the pipe read or the event callback
        # raised): nobody is left to read the child's stdout or observe its
        # exit, so it must be stopped and reaped here — otherwise it would keep
        # burning CPU on pagination for a result no one will use, then linger
        # as a zombie.
        def abort_run
          pid = @mutex.synchronize { @pid }
          return unless pid

          terminate(pid)
          reap_with_escalation(pid)
          @mutex.synchronize { @pid = nil }
        end

        # TERM is advisory; a child stuck in uninterruptible work is force-
        # killed after a bounded grace period so the supervising worker thread
        # can never hang on the reap.
        def reap_with_escalation(pid)
          deadline = monotonic_now + KILL_ESCALATION_SECONDS
          until Process.waitpid(pid, Process::WNOHANG)
            return force_kill(pid) if monotonic_now >= deadline

            sleep(REAP_POLL_INTERVAL_SECONDS)
          end
        rescue Errno::ECHILD => e
          record_batch_error(e)
        end

        def force_kill(pid)
          Process.kill('KILL', pid)
          await_exit(pid)
        rescue Errno::ESRCH, Errno::EPERM => e
          record_batch_error(e)
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def terminate(pid)
          Process.kill('TERM', pid)
        rescue Errno::ESRCH, Errno::EPERM => e
          # Already gone (or unreachable): cancellation's goal is met either
          # way; record it for the curious.
          record_batch_error(e)
        end

        def record_batch_error(error)
          @logger&.debug('prepagination_batch_process.failed',
                         error: error.class.name, message: error.message)
        end
      end
    end
  end
end
