# frozen_string_literal: true

require_relative 'book_finder'
require_relative '../../application/ports/outbound/library_scanner'
require_relative '../../application/ports/outbound/async_executor'
require_relative '../../application/ports/outbound/background_worker_builder'

module Shoko
  module Adapters
    module BookSources
      # Handles ebook library scanning operations (filesystem/OS concerns)
      class LibraryScanner
        include Application::Ports::Outbound::LibraryScanner

        attr_reader :scan_status, :scan_message
        attr_accessor :epubs
        alias books epubs
        alias books= epubs=

        # @param executor [Application::Ports::Outbound::AsyncExecutor, nil] Background executor
        # @param background_worker_builder [Application::Ports::Outbound::BackgroundWorkerBuilder, nil]
        # @param logger [Application::Ports::Outbound::Logging, nil] Logger adapter
        # @param book_finder [#scan_system] Finder dependency for scanning/cache operations
        def initialize(executor: nil, background_worker_builder: nil, logger: nil, book_finder: BookFinder)
          if executor && !executor.is_a?(Shoko::Application::Ports::Outbound::AsyncExecutor)
            raise ArgumentError, 'executor must implement Application::Ports::Outbound::AsyncExecutor when provided'
          end

          if background_worker_builder &&
             !background_worker_builder.is_a?(Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder)
            raise ArgumentError,
                  'background_worker_builder must implement Application::Ports::Outbound::BackgroundWorkerBuilder'
          end
          if executor.nil? && background_worker_builder.nil?
            raise Shoko::ConfigurationError, 'LibraryScanner requires executor or background_worker_builder'
          end

          @epubs = []
          @filtered_epubs = []
          @scan_status = :idle
          @scan_message = ''
          @scan_in_progress = false
          @scan_results_queue = Queue.new
          @scan_mutex = Mutex.new
          @executor = executor
          @background_worker_builder = background_worker_builder
          @executor_owned = false
          @logger = logger
          @book_finder = book_finder
        end

        def load_cached
          @epubs = cached_book_entries
          @filtered_epubs = @epubs
          @scan_status = @epubs.empty? ? :idle : :done
          @scan_message = @scan_status == :done ? "Loaded #{@epubs.length} books from cache" : ''
        rescue StandardError => e
          handle_cache_load_error(e)
        end

        def start_scan(force: false, preserve_entries: false)
          return if scan_in_progress?

          initialize_scan(preserve_entries: preserve_entries)
          submit_scan_job(force)
        end

        private

        def cached_book_entries
          if @book_finder.respond_to?(:load_cached_files)
            @book_finder.load_cached_files(allow_expired: true) || []
          else
            @book_finder.scan_system(force_refresh: false) || []
          end
        end

        def initialize_scan(preserve_entries:)
          @scan_status = :scanning
          @scan_message = 'Scanning for ebooks...'
          return if preserve_entries

          @epubs = []
          @filtered_epubs = []
        end

        def submit_scan_job(force)
          mark_scan_in_progress(true)
          executor = ensure_executor
          executor.submit do
            perform_scan_operation(force)
          rescue StandardError => e
            handle_scan_error(e)
          ensure
            mark_scan_in_progress(false)
          end
        rescue StandardError => e
          mark_scan_in_progress(false)
          handle_scan_submission_error(e)
        end

        def perform_scan_operation(force)
          epubs = @book_finder.scan_system(force_refresh: force) || []
          sorted_epubs = epubs.sort_by { |e| (e['name'] || '').downcase }

          @scan_results_queue.push(status: :done, epubs: sorted_epubs, message: "Found #{sorted_epubs.length} books")
        end

        def handle_scan_error(error)
          @scan_results_queue.push(status: :error, epubs: [], message: "Scan failed: #{error.message[0..50]}")
        end

        def handle_scan_submission_error(error)
          update_scan_state(status: :error, message: "Scan failed: #{error.message[0..50]}")
        end

        def handle_cache_load_error(error)
          @epubs = []
          @filtered_epubs = []
          update_scan_state(status: :error, message: "Cache load failed: #{error.message}")
        end

        public

        def process_results
          return if @scan_results_queue.empty?

          result = @scan_results_queue.pop
          update_scan_state(status: result[:status], message: result[:message])
          return result[:epubs] if result[:status] == :done

          nil
        end

        def cleanup
          mark_scan_in_progress(false)
          @executor.shutdown if @executor_owned && @executor
          @executor = nil
        end

        def entries
          @epubs
        end

        def update_entries(entries)
          @epubs = entries
        end

        def update_scan_state(status:, message:)
          @scan_status = status
          @scan_message = message
        end

        private

        def scan_in_progress?
          @scan_mutex.synchronize { @scan_in_progress }
        end

        def mark_scan_in_progress(value)
          @scan_mutex.synchronize { @scan_in_progress = value }
        end

        def ensure_executor
          return @executor if @executor

          @executor_owned = true
          @executor = build_owned_executor
        end

        def build_owned_executor
          @background_worker_builder.build(logger: @logger, name: 'library-scan-worker')
        end
      end
    end
  end
end
