# frozen_string_literal: true

require_relative '../../../core/ports/outbound/catalog_refresh_control'
require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/menu_session_store'
require_relative '../../../core/ports/outbound/menu_transient_store'
require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/models/session/menu_state_partition'
require_relative '../../../shared/download_source_policy'

module Shoko
  module Application
    module Workflows
      module Menu
        class DownloadWorkflow
          MIN_PROGRESS_DELTA = 0.01

          def initialize(download_service:, app_config_store:, menu_session_store:, catalog_refresh_control:,
                         menu_transient_store: nil, text_sanitizer: nil, path_ops: nil, logger: nil)
            raise ArgumentError, 'download_service is required' if download_service.nil?
            unless app_config_store.is_a?(Shoko::Core::Ports::Outbound::AppConfigStore)
              raise ArgumentError, 'app_config_store must implement Core::Ports::Outbound::AppConfigStore'
            end
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end
            if !menu_transient_store.nil? &&
               !menu_transient_store.is_a?(Shoko::Core::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Core::Ports::Outbound::MenuTransientStore'
            end

            @download_service = download_service
            @app_config_store = app_config_store
            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
            raise ArgumentError, 'catalog_refresh_control is required' if catalog_refresh_control.nil?
            unless catalog_refresh_control.is_a?(Shoko::Core::Ports::Outbound::CatalogRefreshControl)
              raise ArgumentError,
                    'catalog_refresh_control must implement Core::Ports::Outbound::CatalogRefreshControl'
            end

            @catalog_refresh_control = catalog_refresh_control
            @text_sanitizer = text_sanitizer
            @path_ops = path_ops
            @logger = logger
          end

          def search_downloads(query:, page_url: nil)
            source = current_download_source
            normalized_query = query.to_s.strip
            update_download_state(
              download_status: :searching,
              download_message: "Searching #{download_source_label(source)}...",
              download_progress: 0.0,
              download_results: [],
              download_count: 0,
              download_next: nil,
              download_prev: nil,
              download_selected: 0
            )

            if source == :libgen && normalized_query.length < 3
              update_download_state(
                download_status: :error,
                download_message: 'Libgen search needs at least 3 characters',
                download_progress: 0.0
              )
              return
            end

            result = @download_service.search(query: query, source: source, page_url: page_url)
            message = if result[:books].empty?
                        "No #{download_source_label(source)} results"
                      else
                        "Found #{result[:books].length} of #{result[:count]} on #{download_source_label(source)}"
                      end
            update_download_state(
              download_results: result[:books],
              download_count: result[:count],
              download_next: result[:next],
              download_prev: result[:previous],
              download_selected: 0,
              download_status: :done,
              download_message: message,
              download_progress: 0.0
            )
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
            update_download_state(download_status: :downloading,
                                  download_message: "Downloading #{title} from #{download_source_label(source)}...",
                                  download_progress: 0.0)

            last_progress = nil
            result = @download_service.download(book, source: source) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              next unless publish_progress?(progress, last_progress)

              percent = total.to_i.positive? ? (progress * 100).round : nil
              base_message = "Downloading #{title} from #{download_source_label(source)}..."
              message = percent ? "#{base_message} #{percent}%" : base_message
              update_download_state(download_progress: progress, download_message: message)
              last_progress = progress
            end

            downloaded_message = result[:existing] ? 'Already downloaded' : "Saved to #{path_basename(result[:path])}"
            update_download_state(download_status: :done,
                                  download_message: downloaded_message,
                                  download_progress: 0.0)
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

          def current_menu
            return @menu_session_store.load unless @menu_transient_store

            Shoko::Core::Models::Session::MenuSnapshot.build(
              @menu_session_store.load.to_h.merge(@menu_transient_store.load.to_h)
            )
          end

          def persist_menu_payload(payload)
            return @menu_session_store.save(current_menu.with(**payload)) unless @menu_transient_store

            session_attributes, transient_attributes =
              Shoko::Core::Models::Session::MenuStatePartition.split(payload)
            previous_session = @menu_session_store.load
            previous_transient = @menu_transient_store.load

            @menu_session_store.save(previous_session.with(**session_attributes)) unless session_attributes.empty?
            if transient_attributes.any?
              @menu_transient_store.save(previous_transient.with(**transient_attributes))
            end
          rescue Shoko::Error, ArgumentError
            rollback_menu_payload(previous_session, previous_transient, session_attributes, transient_attributes)
            raise
          end

          def rollback_menu_payload(previous_session, previous_transient, session_attributes, transient_attributes)
            if previous_session && session_attributes && session_attributes.any?
              @menu_session_store.save(previous_session)
            end
            return unless previous_transient && transient_attributes && !transient_attributes.empty?

            @menu_transient_store.save(previous_transient)
          rescue Shoko::Error, ArgumentError => e
            @last_menu_payload_rollback_error = e
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
