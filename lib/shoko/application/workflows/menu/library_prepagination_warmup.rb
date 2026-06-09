# frozen_string_literal: true

require_relative '../../../shared/errors'
require_relative '../../ports/outbound/cache_availability'
require_relative '../../ports/outbound/document_loader'
require_relative '../../ports/outbound/reader_runtime_context'
require_relative '../../ports/outbound/prepagination_progress_writer'
require_relative '../../ports/outbound/background_worker_builder'
require_relative '../../ports/outbound/clock'

module Shoko
  module Application
    module Workflows
      module Menu
        # Opt-in eager pre-pagination: when the user enables "Pre-paginate Library"
        # and the terminal size has changed since the last run, rebuild the page
        # maps for every already-cached book in the background so opening any of
        # them at the new size is instant (a cache hit) instead of triggering an
        # on-open recalculation.
        #
        # Runs on its own worker thread with an isolated pagination stack (a
        # dedicated page calculator), so it never touches the reader's shared
        # singletons even if the user opens a book while it runs.
        #
        # Politeness is the whole point of this class. Pagination is CPU-bound and
        # Ruby's GIL means even a "background" thread starves the UI while it holds
        # the interpreter. So the worker (a) runs at low priority, (b) waits out an
        # initial settle window so the menu can paint and scan first, and — most
        # importantly — (c) releases the GIL after *every chapter*, sleeping in
        # proportion to the work just done. That hands the CPU back to the render
        # thread continuously, so the user keeps browsing without a freeze; heavier
        # chapters simply buy the UI proportionally longer breathing room. Every
        # step is also defensive: the feature is off by default, so a failure must
        # never take down the menu — at worst pre-pagination silently does nothing.
        class LibraryPrepaginationWarmup
          # Tunable background-politeness knobs. Defaults keep the UI responsive;
          # tests pass an all-zero throttle so they neither sleep nor renice the
          # test thread.
          Throttle = Data.define(
            :worker_priority,  # Thread#priority for the worker (nil = leave as-is)
            :startup_settle,   # seconds to wait before the first book
            :chapter_ratio,    # sleep this multiple of each chapter's build time
            :min_yield,        # floor on the per-chapter GIL release (seconds)
            :max_yield,        # cap on the per-chapter GIL release (seconds)
            :inter_book_pause  # seconds to rest between books
          )
          DEFAULT_THROTTLE = Throttle.new(
            worker_priority: -3,
            startup_settle: 2.0,
            chapter_ratio: 2.0,
            min_yield: 0.004,
            max_yield: 0.25,
            inter_book_pause: 0.03
          ).freeze

          Dependencies = Data.define(
            :catalog_service, :cache_availability, :document_loader, :page_calculator,
            :app_config_store, :reader_runtime_context, :progress_writer,
            :background_worker_builder, :clock, :logger
          )

          def initialize(deps:, throttle: DEFAULT_THROTTLE)
            validate_ports!(deps)
            @catalog_service = deps.catalog_service
            @cache_availability = deps.cache_availability
            @document_loader = deps.document_loader
            @page_calculator = deps.page_calculator
            @app_config_store = deps.app_config_store
            @reader_runtime_context = deps.reader_runtime_context
            @progress_writer = deps.progress_writer
            @background_worker_builder = deps.background_worker_builder
            @clock = deps.clock
            @logger = deps.logger
            @throttle = throttle
            @cancelled = false
            @worker = nil
          end

          # Kick off the batch on a background thread when warranted. Safe to call
          # unconditionally on menu startup; returns without work when the feature
          # is off or the library is already paginated at the current size.
          def start
            config = @app_config_store.load
            return :disabled unless config.prepaginate_on_resize

            width, height = current_dimensions
            return :no_size unless width.positive? && height.positive?

            signature = "#{width}x#{height}"
            return :unchanged if config.last_paginated_size.to_s == signature

            @cancelled = false
            worker.submit { run(width, height, signature) }
            :started
          rescue Shoko::Error => e
            log('start_failed', e)
            :error
          end

          # Stop between books and tear the worker down (called when the menu exits,
          # e.g. a book is opened or the app quits) so the batch never outlives the
          # menu or competes with an active reader.
          def cancel
            @cancelled = true
            shutdown_worker
          end

          private

          def run(width, height, signature)
            apply_worker_politeness
            yield_to_foreground(@throttle.startup_settle)
            return if @cancelled

            paths = candidate_paths
            process_books(paths, width, height) if paths.any?
            persist_signature(signature) unless @cancelled
          rescue Shoko::Error => e
            log('run_failed', e)
          ensure
            @progress_writer.finish
          end

          def process_books(paths, width, height)
            @progress_writer.start(total: paths.length, paths: paths)
            paths.each_with_index do |path, index|
              break if @cancelled

              paginate_book(path, width, height)
              @progress_writer.report(done: index + 1)
              yield_to_foreground(@throttle.inter_book_pause)
            end
          end

          def candidate_paths
            entries = Array(@catalog_service.cached_library_entries)
            paths = entries.filter_map { |entry| book_path_from(entry) }.uniq
            paths.select { |path| cached?(path) }
          rescue Shoko::Error => e
            log('candidate_paths_failed', e)
            []
          end

          def book_path_from(entry)
            return nil unless entry.is_a?(Hash)

            entry[:book_path] || entry[:epub_path]
          end

          def cached?(path)
            @cache_availability.cache_available?(path) == true
          end

          # Build (and persist) the page map for one cached book at the current
          # size. The per-chapter callback is the cooperative yield point that keeps
          # the UI responsive; the page calculator also skips the heavy work when
          # the layout is already cached, so re-running an unchanged book is cheap.
          def paginate_book(path, width, height)
            document = @document_loader.load(path: path)
            return unless document&.cached?

            config = @app_config_store.load
            @page_calculator.reset_session!
            yielder = chapter_yielder
            if config.page_numbering_mode == :absolute
              @page_calculator.build_absolute_map!(width, height, document, config_reader: config, &yielder)
            else
              @page_calculator.build_dynamic_map!(width, height, document, sidebar_visible: false,
                                                                          config_reader: config, &yielder)
            end
          rescue Shoko::Error => e
            log('paginate_book_failed', e, path: path)
          end

          # Returns a per-chapter callback that releases the GIL for a spell
          # proportional to how long that chapter took to build (clamped), so the
          # render thread interleaves smoothly even on a large book.
          def chapter_yielder
            last = monotonic_now
            lambda do |_done, _total|
              elapsed = monotonic_now - last
              yield_to_foreground((elapsed * @throttle.chapter_ratio).clamp(@throttle.min_yield, @throttle.max_yield))
              last = monotonic_now
            end
          end

          def apply_worker_politeness
            priority = @throttle.worker_priority
            Thread.current.priority = priority unless priority.nil?
          rescue Shoko::Error => e
            log('apply_worker_politeness_failed', e)
          end

          def yield_to_foreground(seconds)
            return if @cancelled

            sleep(seconds) if seconds.to_f.positive?
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

          def monotonic_now
            @clock.monotonic_now
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
            contract!(deps.cache_availability, Ports::Outbound::CacheAvailability, 'cache_availability')
            contract!(deps.document_loader, Ports::Outbound::DocumentLoader, 'document_loader')
            contract!(deps.reader_runtime_context, Ports::Outbound::ReaderRuntimeContext, 'reader_runtime_context')
            contract!(deps.progress_writer, Ports::Outbound::PrepaginationProgressWriter, 'progress_writer')
            contract!(deps.background_worker_builder, Ports::Outbound::BackgroundWorkerBuilder, 'background_worker_builder')
            contract!(deps.clock, Ports::Outbound::Clock, 'clock')
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
