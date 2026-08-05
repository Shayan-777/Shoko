# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Owns one catalog lookup/download/install operation, including its
          # progress and redraw-throttle state.
          class DatasetInstaller
            def initialize(catalog:, storage:, config_reader:, clock:, callbacks:)
              @catalog = catalog
              @storage = storage
              @config_reader = config_reader
              @clock = clock
              @callbacks = callbacks
              @last_draw_at = nil
            end

            def install(source:, target:)
              install_dataset?(source, target)
            rescue Shoko::Error => e
              notify_failure("Download failed: #{e.message}")
              false
            ensure
              @last_draw_at = nil
            end

            private

            def install_dataset?(source, target)
              unless @catalog
                notify_failure('Dictionary catalog unavailable.')
                return false
              end

              announce_lookup(source, target)
              entry = find_entry(@catalog.list_remote, source, target)
              unless entry
                notify_failure("No dictionary dataset found for #{source}-#{target}.")
                return false
              end

              name = entry[:name] || "#{source}-#{target}.sqlite3"
              download(entry, name, source, target)
              publish(source, target, status: "Installed #{name}", status_level: :success, progress: 1.0)
              @callbacks.fetch(:complete).call(source, target)
              true
            end

            def announce_lookup(source, target)
              publish(source, target, status: "Looking for #{source}-#{target} dataset...", progress: 0.0,
                                      prompt: '', input_value: '')
            end

            def notify_failure(message)
              @callbacks.fetch(:error).call(message)
            end

            def download(entry, name, source, target)
              @last_draw_at = monotonic_now
              @catalog.download(entry, storage_path) do |done, total|
                progress, message = progress_message(done, total, name)
                publish(source, target, status: message, progress: progress, redraw: false)
                redraw_if_due(progress)
              end
            end

            def find_entry(items, source, target)
              Array(items).find do |item|
                @callbacks.fetch(:normalize).call(item[:source]) == source &&
                  @callbacks.fetch(:normalize).call(item[:target]) == target
              end
            end

            def storage_path
              @storage&.ensure_databases_path(@config_reader.dictionary_path)
            end

            def progress_message(done, total, name)
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              percent = total.to_i.positive? ? (progress * 100).round : nil
              [progress, percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."]
            end

            def redraw_if_due(progress)
              now = monotonic_now
              return if (now - @last_draw_at) < 0.08 && progress < 1.0

              @callbacks.fetch(:draw).call
              @last_draw_at = now
            end

            def publish(source, target, **attributes)
              @callbacks.fetch(:publish).call(source: source, target: target, **attributes)
            end

            def monotonic_now = @clock.monotonic_now
          end
        end
      end
    end
  end
end
