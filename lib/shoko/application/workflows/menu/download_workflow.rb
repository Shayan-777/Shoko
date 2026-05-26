# frozen_string_literal: true

require_relative '../../../application/ports/outbound/catalog_refresh_control'
require_relative '../../../application/ports/outbound/app_config_store'
require_relative '../../../application/ports/outbound/menu_session_store'
require_relative '../../../application/ports/outbound/menu_transient_store'
require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/models/session/menu_state_partition'
require_relative '../../../shared/download_source_policy'
require_relative 'menu_state_persistence'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side book search/download state and catalog refresh.
        class DownloadWorkflow
          MIN_PROGRESS_DELTA = 0.01
          include MenuStatePersistence

          def initialize(download_service:, app_config_store:, menu_session_store:, catalog_refresh_control:,
                         menu_transient_store:, text_sanitizer: nil, path_ops: nil, logger: nil)
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
            @text_sanitizer = text_sanitizer
            @path_ops = path_ops
            @logger = logger
          end

          def search_downloads(query:, page_url: nil)
            source = current_download_source
            normalized_query = query.to_s.strip
            update_download_state(search_started_payload(source))

            validation_error = search_validation_error(source, normalized_query)
            return update_download_state(search_error_payload(validation_error)) if validation_error

            result = @download_service.search(query: query, source: source, page_url: page_url)
            update_download_state(search_result_payload(source, result))
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('search_downloads', e, query: query, page_url: page_url)
            update_download_state(download_status: :error,
                                  download_message: "Search failed: #{e.message}",
                                  download_progress: 0.0)
          end

          def download_book(book)
            title = safe_book_title(book)
            source = source_for_book(book)
            update_download_state(download_started_payload(title, source))

            result = download_result(book, title, source)
            update_download_state(download_completed_payload(result))
            @catalog_refresh_control.refresh_catalog(force: true)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('download_book', e, book: summarize_book_payload(book))
            update_download_state(download_status: :error,
                                  download_message: "Download failed: #{e.message}",
                                  download_progress: 0.0)
          end

          private

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

          def download_result(book, title, source)
            last_progress = nil
            @download_service.download(book, source: source) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              next unless publish_progress?(progress, last_progress)

              update_download_state(download_progress_payload(title, source, progress, total))
              last_progress = progress
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

          def publish_progress?(progress, last_progress)
            return true if last_progress.nil?
            return true if progress >= 1.0

            (progress - last_progress).abs >= MIN_PROGRESS_DELTA
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

            book.each_with_object({}) do |(key, value), acc|
              normalized_key = key.is_a?(String) ? key.to_sym : key
              acc[normalized_key] = value
            end
          end

          def invalid_download_payload(message)
            Shoko::FatalExternalInputError.new(message, source: :download_payload)
          end

          def summarize_book_payload(book)
            return book.class.name unless book.is_a?(Hash)

            normalized = book.each_with_object({}) do |(key, value), acc|
              normalized_key = key.is_a?(String) ? key.to_sym : key
              acc[normalized_key] = value
            end
            title = normalized[:title].to_s.strip
            title.empty? ? '<missing-title>' : title
          end
        end
      end
    end
  end
end
