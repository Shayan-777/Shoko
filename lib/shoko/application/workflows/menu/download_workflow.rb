# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_workflow_runtime'
require_relative '../../../core/ports/outbound/menu_workflow_state_writer'

module Shoko
  module Application
    module Workflows
      module Menu
        class DownloadWorkflow
          def initialize(download_service:, menu_state_writer:, menu_runtime:, clock:, text_sanitizer: nil,
                         path_ops: nil, logger: nil)
            raise ArgumentError, 'download_service is required' if download_service.nil?

            @download_service = download_service
            unless menu_state_writer.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
              raise ArgumentError, 'menu_state_writer must implement Core::Ports::Outbound::MenuWorkflowStateWriter'
            end

            @menu_state_writer = menu_state_writer
            raise ArgumentError, 'menu_runtime is required' if menu_runtime.nil?
            unless menu_runtime.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowRuntime)
              raise ArgumentError, 'menu_runtime must implement Core::Ports::Outbound::MenuWorkflowRuntime'
            end

            @menu_runtime = menu_runtime
            @text_sanitizer = text_sanitizer
            @path_ops = path_ops
            @logger = logger
            raise ArgumentError, 'clock is required' if clock.nil?

            @clock = clock
          end

          def search_downloads(query:, page_url: nil)
            update_download_state(
              download_status: :searching,
              download_message: 'Searching Gutendex...',
              download_progress: 0.0,
              download_results: [],
              download_count: 0,
              download_next: nil,
              download_prev: nil,
              download_selected: 0
            )
            draw_screen

            result = @download_service.search(query: query, page_url: page_url)
            message = if result[:books].empty?
                        'No results'
                      else
                        "Found #{result[:books].length} of #{result[:count]}"
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
          ensure
            draw_screen
          end

          def download_book(book)
            title = safe_book_title(book)
            update_download_state(download_status: :downloading,
                                  download_message: "Downloading #{title}...",
                                  download_progress: 0.0)
            draw_screen

            last_draw = monotonic_now
            result = @download_service.download(book) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              now = monotonic_now
              next if (now - last_draw) < 0.08 && progress < 1.0

              percent = total.to_i.positive? ? (progress * 100).round : nil
              message = percent ? "Downloading #{title}... #{percent}%" : "Downloading #{title}..."
              update_download_state(download_progress: progress, download_message: message)
              draw_screen
              last_draw = now
            end

            downloaded_message = result[:existing] ? 'Already downloaded' : "Saved to #{path_basename(result[:path])}"
            update_download_state(download_status: :done,
                                  download_message: downloaded_message,
                                  download_progress: 0.0)
            refresh_scan(force: true)
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('download_book', e, book: summarize_book_payload(book))
            update_download_state(download_status: :error,
                                  download_message: "Download failed: #{e.message}",
                                  download_progress: 0.0)
          ensure
            draw_screen
          end

          private

          def update_download_state(payload)
            @menu_state_writer.set_download_state(payload)
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

          def monotonic_now
            @clock.monotonic_now
          end

          def draw_screen
            @menu_runtime.draw_screen
          end

          def refresh_scan(force:)
            @menu_runtime.refresh_scan(force: force)
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
