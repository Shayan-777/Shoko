# frozen_string_literal: true

require_relative 'progress_throttle'
require 'shoko/application/ports/outbound/catalog_refresh_control'
require 'shoko/shared/hash_normalizer'
require 'shoko/application/ports/outbound/app_config_store'
require 'shoko/application/ports/outbound/menu_session_store'
require 'shoko/application/ports/outbound/menu_transient_store'
require_relative '../../ports/outbound/state/menu_snapshot'
require_relative '../../ports/outbound/state/menu_state_partition'
require 'shoko/shared/download_source_policy'
require 'shoko/shared/errors'
require_relative '../../services/async_result_relay'
require_relative 'menu_state_persistence'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side book search/download state and catalog refresh.
        #
        # Search and download run through an AsyncResultRelay: the network work
        # happens on a worker thread while the menu keeps processing input
        # (Esc cancels an active download); every state write still happens on
        # the menu thread when the relay drains. Without a relay executor the
        # workflow stays fully synchronous.
        class DownloadWorkflow
          include MenuStatePersistence

          # Raised inside the worker's progress callback to abort a download
          # the user cancelled; the .part streaming guarantees no partial file
          # survives the abort.
          class DownloadCancelledError < Shoko::Error; end

          def initialize(download_service:, app_config_store:, menu_session_store:, catalog_refresh_control:,
                         menu_transient_store:, async_relay: nil, text_sanitizer: nil, path_ops: nil, logger: nil)
            raise ArgumentError, 'download_service is required' if download_service.nil?
            unless app_config_store.is_a?(Shoko::Application::Ports::Outbound::AppConfigStore)
              raise ArgumentError, 'app_config_store must implement Application::Ports::Outbound::AppConfigStore'
            end
            unless menu_session_store.is_a?(Shoko::Application::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore'
            end
            unless menu_transient_store.is_a?(Shoko::Application::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Application::Ports::Outbound::MenuTransientStore'
            end

            @download_service = download_service
            @app_config_store = app_config_store
            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
            raise ArgumentError, 'catalog_refresh_control is required' if catalog_refresh_control.nil?

            unless catalog_refresh_control.is_a?(Shoko::Application::Ports::Outbound::CatalogRefreshControl)
              raise ArgumentError, 'catalog_refresh_control must implement Application::Ports::Outbound::CatalogRefreshControl'
            end

            @catalog_refresh_control = catalog_refresh_control
            @async_relay = async_relay || Shoko::Application::Services::AsyncResultRelay.new(logger: logger)
            @text_sanitizer = text_sanitizer
            @path_ops = path_ops
            @logger = logger
            @network_in_flight = false
            @cancel_requested = false
          end

          def search_downloads(query:, page_url: nil)
            return notify_network_busy if network_in_flight?

            source = current_download_source
            normalized_query = query.to_s.strip
            update_download_state(search_started_payload(source))

            validation_error = search_validation_error(source, normalized_query)
            return update_download_state(search_error_payload(validation_error)) if validation_error

            begin_network_request
            @async_relay.submit { perform_search(query, source, page_url) }
          end

          def download_book(book)
            return notify_network_busy if network_in_flight?

            title = safe_book_title(book)
            source = source_for_book(book)
            update_download_state(download_started_payload(title, source))

            begin_network_request
            @async_relay.submit { perform_download(book, title, source) }
          end

          # Applies any results the worker produced; called from the menu loop
          # on the UI thread.
          def process_pending_events
            @async_relay.drain!
          end

          # True while a search/download is running or has undrained results.
          def network_pending?
            @async_relay.busy? || network_in_flight?
          end

          # Requests cancellation of the active download (Esc). The worker's
          # progress callback notices the flag and aborts the stream.
          def cancel_active_download
            return false unless network_in_flight?

            @cancel_requested = true
            true
          end

          private

          # ----- worker-side network jobs (no state writes; enqueue only) -----

          def perform_search(query, source, page_url)
            result = @download_service.search(query: query, source: source, page_url: page_url)
            @async_relay.enqueue do
              finish_network_request
              update_download_state(search_result_payload(source, result))
            end
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            relay_search_failure(e, query, page_url)
          end

          def perform_download(book, title, source)
            result = download_result(book, title, source)
            @async_relay.enqueue do
              finish_network_request
              update_download_state(download_completed_payload(result))
              @catalog_refresh_control.refresh_catalog(force: true)
            end
          rescue DownloadCancelledError
            relay_download_cancelled(title, source)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            relay_download_failure(e, book)
          end

          def relay_search_failure(error, query, page_url)
            @async_relay.enqueue do
              finish_network_request
              log_resilient('search_downloads', error, query: query, page_url: page_url)
              update_download_state(download_status: :error,
                                    download_message: "Search failed: #{error.message}",
                                    download_progress: 0.0)
            end
          end

          def relay_download_failure(error, book)
            @async_relay.enqueue do
              finish_network_request
              log_resilient('download_book', error, book: summarize_book_payload(book))
              update_download_state(download_status: :error,
                                    download_message: "Download failed: #{error.message}",
                                    download_progress: 0.0)
            end
          end

          def relay_download_cancelled(title, source)
            @async_relay.enqueue do
              finish_network_request
              update_download_state(download_status: :idle,
                                    download_message: "Cancelled download of #{title} from #{download_source_label(source)}",
                                    download_progress: 0.0)
            end
          end

          # ----- in-flight bookkeeping (UI thread) -----

          def network_in_flight?
            @network_in_flight
          end

          def begin_network_request
            @network_in_flight = true
            @cancel_requested = false
          end

          def finish_network_request
            @network_in_flight = false
            @cancel_requested = false
          end

          def notify_network_busy
            update_download_state(download_message: 'A search or download is already running…')
          end

          def update_download_state(payload)
            persist_menu_payload(payload)
          end

          def search_started_payload(source)
            {
              download_status: :searching,
              download_message: "Searching #{download_source_label(source)}...",
              download_progress: 0.0,
              download_results: [],
              download_count: 0,
              download_next: nil,
              download_prev: nil,
              download_selected: 0,
            }
          end

          def search_validation_error(source, normalized_query)
            return nil unless source == :libgen && normalized_query.length < 3

            'Libgen search needs at least 3 characters'
          end

          def search_error_payload(message)
            {
              download_status: :error,
              download_message: message,
              download_progress: 0.0,
            }
          end

          def search_result_payload(source, result)
            books = Array(result[:books])
            {
              download_results: books,
              download_count: result[:count],
              download_next: result[:next],
              download_prev: result[:previous],
              download_selected: 0,
              download_status: :done,
              download_message: search_result_message(source, books.length, result[:count]),
              download_progress: 0.0,
            }
          end

          def search_result_message(source, books_count, total_count)
            label = download_source_label(source)
            return "No #{label} results" if books_count.zero?

            "Found #{books_count} of #{total_count} on #{label}"
          end

          def current_download_source
            snapshot = @app_config_store.load
            Shoko::Shared::DownloadSourcePolicy.normalize(snapshot.download_source) ||
              Shoko::Shared::DownloadSourcePolicy.default_id
          end

          def source_for_book(book)
            normalized = normalize_book_payload(book)
            source = normalized[:source]
            Shoko::Shared::DownloadSourcePolicy.normalize(source) || current_download_source
          end

          def download_source_label(source)
            Shoko::Shared::DownloadSourcePolicy.label_for(source)
          end

          def safe_book_title(book)
            normalized = normalize_book_payload(book)
            title = normalized[:title].to_s.strip
            raise invalid_download_payload('download payload missing title') if title.empty?

            if @text_sanitizer
              @text_sanitizer.sanitize(title, preserve_newlines: false, max_length: nil)
            else
              title
            end
          end

          def path_basename(path)
            return path.to_s unless @path_ops

            @path_ops.basename(path)
          end

          def download_started_payload(title, source)
            {
              download_status: :downloading,
              download_message: download_message(title, source),
              download_progress: 0.0,
            }
          end

          # Runs on the worker thread: progress is throttled here and enqueued
          # for the UI thread to apply; the cancel flag aborts the stream.
          def download_result(book, title, source)
            last_progress = nil
            @download_service.download(book, source: source) do |done, total|
              raise DownloadCancelledError, 'download cancelled' if @cancel_requested

              progress = total.to_i.positive? ? done.to_f / total : 0.0
              next unless ProgressThrottle.publish?(progress, last_progress)

              last_progress = progress
              @async_relay.enqueue { update_download_state(download_progress_payload(title, source, progress, total)) }
            end
          end

          def download_progress_payload(title, source, progress, total)
            percent = total.to_i.positive? ? (progress * 100).round : nil
            message = percent ? "#{download_message(title, source)} #{percent}%" : download_message(title, source)
            { download_progress: progress, download_message: message }
          end

          def download_completed_payload(result)
            {
              download_status: :done,
              download_message: download_result_message(result),
              download_progress: 0.0,
            }
          end

          def download_message(title, source)
            "Downloading #{title} from #{download_source_label(source)}..."
          end

          def download_result_message(result)
            result[:existing] ? 'Already downloaded' : "Saved to #{path_basename(result[:path])}"
          end

          def log_resilient(operation, error, **metadata)
            @logger&.error(
              "menu.download_workflow.#{operation}_failed",
              error: error.class.name,
              message: error.message,
              **metadata
            )
          end

          def normalize_book_payload(book)
            raise invalid_download_payload("download payload must be a Hash, got #{book.class}") unless book.is_a?(Hash)

            Shoko::Shared::HashNormalizer.symbolize_keys(book)
          end

          def invalid_download_payload(message)
            Shoko::FatalExternalInputError.new(message, source: :download_payload)
          end

          def summarize_book_payload(book)
            return book.class.name unless book.is_a?(Hash)

            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(book)
            title = normalized[:title].to_s.strip
            title.empty? ? '<missing-title>' : title
          end
        end
      end
    end
  end
end
