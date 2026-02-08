# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        class DownloadWorkflow
          def initialize(download_service:, menu_state_writer:, draw_screen:, refresh_scan:, text_sanitizer: nil)
            @download_service = download_service
            @menu_state_writer = menu_state_writer
            @draw_screen = draw_screen
            @refresh_scan = refresh_scan
            @text_sanitizer = text_sanitizer
          end

          def search_downloads(query:, page_url: nil)
            service = @download_service
            unless service
              update_download_state(download_status: :error, download_message: 'Download service unavailable')
              return
            end

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
            @draw_screen.call

            result = service.search(query: query, page_url: page_url)
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
          rescue StandardError => e
            update_download_state(download_status: :error,
                                  download_message: "Search failed: #{e.message}",
                                  download_progress: 0.0)
          ensure
            @draw_screen.call
          end

          def download_book(book)
            service = @download_service
            unless service
              update_download_state(download_status: :error, download_message: 'Download service unavailable')
              @draw_screen.call
              return
            end

            title = safe_book_title(book)
            update_download_state(download_status: :downloading,
                                  download_message: "Downloading #{title}...",
                                  download_progress: 0.0)
            @draw_screen.call

            last_draw = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = service.download(book) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              next if (now - last_draw) < 0.08 && progress < 1.0

              percent = total.to_i.positive? ? (progress * 100).round : nil
              message = percent ? "Downloading #{title}... #{percent}%" : "Downloading #{title}..."
              update_download_state(download_progress: progress, download_message: message)
              @draw_screen.call
              last_draw = now
            end

            downloaded_message = result[:existing] ? 'Already downloaded' : "Saved to #{File.basename(result[:path])}"
            update_download_state(download_status: :done,
                                  download_message: downloaded_message,
                                  download_progress: 0.0)
            @refresh_scan.call(force: true)
          rescue StandardError => e
            update_download_state(download_status: :error,
                                  download_message: "Download failed: #{e.message}",
                                  download_progress: 0.0)
          ensure
            @draw_screen.call
          end

          private

          def update_download_state(payload)
            @menu_state_writer.update_menu(payload)
          end

          def safe_book_title(book)
            return 'book' unless book.respond_to?(:[])

            title = book[:title] || book['title'] || 'book'
            if @text_sanitizer
              @text_sanitizer.sanitize(title.to_s, preserve_newlines: false, max_length: nil)
            else
              title.to_s
            end
          end
        end
      end
    end
  end
end
