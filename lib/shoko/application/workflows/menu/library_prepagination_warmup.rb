# frozen_string_literal: true

require 'shoko/shared/errors'
require_relative '../../ports/outbound/reader_runtime_context'
require_relative '../../ports/outbound/prepagination_progress_writer'
require_relative '../../ports/outbound/prepagination_batch_runner'
require_relative '../../ports/outbound/background_worker_builder'

module Shoko
  module Application
    module Workflows
      module Menu
        # Opt-in eager pre-pagination: when the user enables "Pre-paginate
        # Library" and the terminal size has changed since the last run,
        # rebuild the page maps for every already-cached book so opening any
        # of them at the new size is instant (a cache hit) instead of
        # triggering an on-open recalculation.
        #
        # The heavy work runs in a separate low-priority OS process (via the
        # batch-runner port) because pagination is CPU-bound and a thread
        # doing it here would hold the GIL and starve the menu's render loop
        # no matter how politely it sleeps. This side only supervises: a
        # worker thread blocks on the child's progress pipe (pure IO, no GIL
        # contention), mirrors events into menu state for the toast, and
        # persists the size signature once the child finishes cleanly.
        # Every step is defensive: the feature is off by default, so a
        # failure must never take down the menu — at worst pre-pagination
        # silently does nothing.
        class LibraryPrepaginationWarmup
          Dependencies = Data.define(
            :batch_runner, :app_config_store, :reader_runtime_context,
            :progress_writer, :background_worker_builder, :logger
          )

          def initialize(deps:)
            validate_ports!(deps)
            @batch_runner = deps.batch_runner
            @app_config_store = deps.app_config_store
            @reader_runtime_context = deps.reader_runtime_context
            @progress_writer = deps.progress_writer
            @background_worker_builder = deps.background_worker_builder
            @logger = deps.logger
            @cancelled = false
            @worker = nil
          end

          # Kick off the batch when warranted. Safe to call unconditionally on
          # menu startup; returns without work when the feature is off or the
          # library is already paginated at the current size.
          def start
            config = @app_config_store.load
            return :disabled unless config.prepaginate_on_resize

            width, height = current_dimensions
            return :no_size unless width.positive? && height.positive?

            signature = "#{width}x#{height}"
            return :unchanged if config.last_paginated_size.to_s == signature

            # Re-arm both cancel latches for this session: the runner's latch
            # (set by every menu exit) persists until this deliberate restart,
            # so a cancel can never leak into the next session and kill its
            # batch at spawn.
            @cancelled = false
            @batch_runner.reset_cancellation
            worker.submit { supervise_batch(width, height, signature) }
            :started
          # resilient-boundary
          rescue StandardError => e
            record_warmup_start_error(e)
          end

          # Starting is best-effort: the worker submit itself can be refused
          # during a teardown race (WorkerStoppedError is a plain
          # StandardError, not a Shoko::Error); the menu proceeds without the
          # batch and reports :error to the caller.
          def record_warmup_start_error(error)
            log('start_failed', error)
            :error
          end

          # Stop the batch child and tear the worker down (called when the
          # menu exits, e.g. a book is opened or the app quits) so the batch
          # never outlives the menu or competes with an active reader.
          def cancel
            @cancelled = true
            cancel_batch_run
            shutdown_worker
          end

          private

          # Runs on the worker thread: blocks on the child process for its
          # lifetime, forwarding progress. Only a clean, uncancelled finish
          # records the new size signature — a killed or crashed child leaves
          # the previous signature so the next menu start retries.
          def supervise_batch(width, height, signature)
            status = @batch_runner.run_batch(
              width: width, height: height, on_event: method(:handle_batch_event)
            )
            persist_signature(signature) if status == :completed && !@cancelled
          rescue Shoko::Error => e
            log('supervise_batch_failed', e)
          ensure
            @progress_writer.finish
          end

          def handle_batch_event(event)
            return if @cancelled

            case event[:event]
            when 'start' then @progress_writer.start(total: event[:total].to_i, paths: Array(event[:paths]))
            when 'report' then @progress_writer.report(done: event[:done].to_i)
            end
          rescue Shoko::Error => e
            log('handle_batch_event_failed', e)
          end

          def cancel_batch_run
            @batch_runner.cancel_batch
          rescue Shoko::Error => e
            log('cancel_batch_failed', e)
          end

          def persist_signature(signature)
            config = @app_config_store.load
            @app_config_store.save(config.with(last_paginated_size: signature))
          rescue Shoko::Error => e
            log('persist_signature_failed', e)
          end

          def current_dimensions
            size = @reader_runtime_context.terminal_size
            [size.width.to_i, size.height.to_i]
          rescue Shoko::Error => e
            log('current_dimensions_failed', e)
            [0, 0]
          end

          def worker
            @worker ||= @background_worker_builder.build(logger: @logger, name: 'library-prepagination')
          end

          def shutdown_worker
            worker_ref = @worker
            @worker = nil
            worker_ref&.shutdown
          rescue Shoko::Error => e
            log('shutdown_worker_failed', e)
          end

          def log(event, error, **data)
            @logger&.debug("library_prepagination.#{event}", error: error.class.name, message: error.message, **data)
          end

          def validate_ports!(deps)
            contract!(deps.batch_runner, Ports::Outbound::PrepaginationBatchRunner, 'batch_runner')
            contract!(deps.reader_runtime_context, Ports::Outbound::ReaderRuntimeContext, 'reader_runtime_context')
            contract!(deps.progress_writer, Ports::Outbound::PrepaginationProgressWriter, 'progress_writer')
            contract!(deps.background_worker_builder, Ports::Outbound::BackgroundWorkerBuilder,
                      'background_worker_builder')
          end

          def contract!(object, port, name)
            return if object.is_a?(port)

            raise ArgumentError, "#{name} must implement #{port.name}"
          end
        end
      end
    end
  end
end
