# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        class DictionaryWorkflow
          def initialize(dictionary_catalog_service:, dictionary_storage:, config_reader:, menu_state_reader:,
                         menu_state_writer:, menu_runtime:, clock:, file_probe: nil, path_ops: nil)
            @dictionary_catalog_service = dictionary_catalog_service
            @dictionary_storage = dictionary_storage
            @config_reader = config_reader
            @menu_state_reader = menu_state_reader
            @menu_state_writer = menu_state_writer
            raise ArgumentError, 'menu_runtime is required' if menu_runtime.nil?

            @menu_runtime = menu_runtime
            @file_probe = file_probe
            @path_ops = path_ops
            raise ArgumentError, 'clock is required' if clock.nil?

            @clock = clock
          end

          def fetch_dictionary_catalog
            service = @dictionary_catalog_service
            unless service
              update_dictionary_state(dictionary_status: :error, dictionary_message: 'Dictionary catalog unavailable')
              draw_screen
              return
            end

            update_dictionary_state(dictionary_status: :loading,
                                    dictionary_message: 'Loading dictionary list...',
                                    dictionary_progress: 0.0,
                                    dictionary_results: [],
                                    dictionary_selected: 0)
            draw_screen

            remote_items = service.list_remote
            results = merge_dictionary_installation(remote_items)
            update_dictionary_state(dictionary_status: :done,
                                    dictionary_message: "Found #{results.length} dictionaries",
                                    dictionary_progress: 0.0,
                                    dictionary_results: results,
                                    dictionary_selected: 0)
          rescue StandardError => e
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Catalog failed: #{e.message}",
                                    dictionary_progress: 0.0)
          ensure
            draw_screen
          end

          def download_dictionary(entry)
            return unless entry

            service = @dictionary_catalog_service
            unless service
              update_dictionary_state(dictionary_status: :error, dictionary_message: 'Dictionary catalog unavailable')
              draw_screen
              return
            end

            name = entry[:name] || entry['name'] || 'dictionary'
            update_dictionary_state(dictionary_status: :downloading,
                                    dictionary_message: "Downloading #{name}...",
                                    dictionary_progress: 0.0)
            draw_screen

            last_draw = monotonic_now
            dest_dir = dictionary_storage_path
            result = service.download(entry, dest_dir) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              now = monotonic_now
              next if (now - last_draw) < 0.08 && progress < 1.0

              percent = total.to_i.positive? ? (progress * 100).round : nil
              message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
              update_dictionary_state(dictionary_progress: progress, dictionary_message: message)
              draw_screen
              last_draw = now
            end

            message = result[:existing] ? 'Already installed' : "Saved to #{path_basename(result[:path])}"
            update_dictionary_state(dictionary_status: :done,
                                    dictionary_message: message,
                                    dictionary_progress: 0.0)
            mark_dictionary_installed(result[:path]) if result[:path]
          rescue StandardError => e
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Download failed: #{e.message}",
                                    dictionary_progress: 0.0)
          ensure
            draw_screen
          end

          private

          def update_dictionary_state(payload)
            @menu_state_writer.update_menu(payload)
          end

          def dictionary_storage_path
            @dictionary_storage&.ensure_databases_path(@config_reader.dictionary_path)
          rescue StandardError
            nil
          end

          def merge_dictionary_installation(remote_items)
            base_path = dictionary_storage_path
            Array(remote_items).filter_map do |item|
              name = item[:name] || item['name']
              next unless name

              path = join_path(base_path, name.to_s)
              installed = file_exists?(path)
              item.merge(installed: installed, path: path)
            end
          end

          def mark_dictionary_installed(path)
            results = Array(@menu_state_reader.dictionary_results)
            return if results.empty?

            updated = results.map do |item|
              next item unless item[:path].to_s == path.to_s

              item.merge(installed: true)
            end
            update_dictionary_state(dictionary_results: updated)
          end

          def file_exists?(path)
            @file_probe&.exist?(path)
          end

          def join_path(*parts)
            return nil unless @path_ops

            @path_ops.join(*parts)
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
        end
      end
    end
  end
end
