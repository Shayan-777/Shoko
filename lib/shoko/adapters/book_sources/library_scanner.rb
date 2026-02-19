# frozen_string_literal: true

require_relative 'book_finder'
require_relative '../../core/services/inline_executor'

module Shoko
  module Adapters::BookSources
    # Handles ebook library scanning operations (filesystem/OS concerns)
    class LibraryScanner
      attr_accessor :scan_status, :scan_message, :epubs
      alias_method :books, :epubs
      alias_method :books=, :epubs=

      # @param executor [Object, nil] Background executor
      # @param logger [Core::Ports::Logging, nil] Logger adapter
      # @param book_finder [#scan_system] Finder dependency for scanning/cache operations
      def initialize(executor: nil, logger: nil, book_finder: BookFinder)
        @epubs = []
        @filtered_epubs = []
        @scan_status = :idle
        @scan_message = ''
        @scan_in_progress = false
        @scan_results_queue = Queue.new
        @scan_mutex = Mutex.new
        @executor = executor
        @executor_owned = false
        @logger = logger
        @book_finder = book_finder
      end

      def load_cached
        @epubs = @book_finder.scan_system(force_refresh: false) || []
        @filtered_epubs = @epubs
        @scan_status = @epubs.empty? ? :idle : :done
        @scan_message = "Loaded #{@epubs.length} books from cache" if @scan_status == :done
      rescue StandardError => e
        @scan_status = :error
        @scan_message = "Cache load failed: #{e.message}"
        @epubs = []
        @filtered_epubs = []
      end

      def start_scan(force: false)
        return if scan_in_progress?

        initialize_scan
        submit_scan_job(force)
      end

      private

      def initialize_scan
        @scan_status = :scanning
        @scan_message = 'Scanning for ebooks...'
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
      rescue StandardError
        mark_scan_in_progress(false)
      end

      def perform_scan_operation(force)
        epubs = @book_finder.scan_system(force_refresh: force) || []
        sorted_epubs = epubs.sort_by { |e| (e['name'] || '').downcase }

        @scan_results_queue.push(
          status: :done,
          epubs: sorted_epubs,
          message: "Found #{sorted_epubs.length} books"
        )
      end

      def handle_scan_error(error)
        @scan_results_queue.push(
          status: :error,
          epubs: [],
          message: "Scan failed: #{error.message[0..50]}"
        )
      end

      public

      def process_results
        return if @scan_results_queue.empty?

        result = @scan_results_queue.pop
        @scan_status = result[:status]
        @scan_message = result[:message]
        result[:epubs]
      end

      def cleanup
        mark_scan_in_progress(false)
        @executor.shutdown if @executor_owned && @executor
        @executor = nil
      rescue StandardError
        nil
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
        @executor = Shoko::Core::Services::InlineExecutor.new
      end
    end
  end
end
