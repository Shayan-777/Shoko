# frozen_string_literal: true

require 'fileutils'

module Shoko
  module Application
    module Workflows
      module Menu
        class DictionaryWorkflow
          def initialize(dictionary_catalog_service:, dictionary_availability:, config_reader:, menu_state_reader:,
                         menu_state_writer:, draw_screen:)
            @dictionary_catalog_service = dictionary_catalog_service
            @dictionary_availability = dictionary_availability
            @config_reader = config_reader
            @menu_state_reader = menu_state_reader
            @menu_state_writer = menu_state_writer
            @draw_screen = draw_screen
          end

          def fetch_dictionary_catalog
            service = @dictionary_catalog_service
            unless service
              update_dictionary_state(dictionary_status: :error, dictionary_message: 'Dictionary catalog unavailable')
              @draw_screen.call
              return
            end

            update_dictionary_state(dictionary_status: :loading,
                                    dictionary_message: 'Loading dictionary list...',
                                    dictionary_progress: 0.0,
                                    dictionary_results: [],
                                    dictionary_selected: 0)
            @draw_screen.call

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
            @draw_screen.call
          end

          def download_dictionary(entry)
            return unless entry

            service = @dictionary_catalog_service
            unless service
              update_dictionary_state(dictionary_status: :error, dictionary_message: 'Dictionary catalog unavailable')
              @draw_screen.call
              return
            end

            name = entry[:name] || entry['name'] || 'dictionary'
            update_dictionary_state(dictionary_status: :downloading,
                                    dictionary_message: "Downloading #{name}...",
                                    dictionary_progress: 0.0)
            @draw_screen.call

            last_draw = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            dest_dir = dictionary_storage_path
            result = service.download(entry, dest_dir) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              next if (now - last_draw) < 0.08 && progress < 1.0

              percent = total.to_i.positive? ? (progress * 100).round : nil
              message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
              update_dictionary_state(dictionary_progress: progress, dictionary_message: message)
              @draw_screen.call
              last_draw = now
            end

            message = result[:existing] ? 'Already installed' : "Saved to #{File.basename(result[:path])}"
            update_dictionary_state(dictionary_status: :done,
                                    dictionary_message: message,
                                    dictionary_progress: 0.0)
            mark_dictionary_installed(result[:path]) if result[:path]
          rescue StandardError => e
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Download failed: #{e.message}",
                                    dictionary_progress: 0.0)
          ensure
            @draw_screen.call
          end

          private

          def update_dictionary_state(payload)
            @menu_state_writer.update_menu(payload)
          end

          def dictionary_storage_path
            dict_avail = @dictionary_availability
            config_path = @config_reader.dictionary_path.to_s.strip
            path = if config_path.empty?
                     dict_avail&.default_databases_path || File.join(Dir.home, '.local', 'share', 'shoko', 'dictionaries')
                   else
                     File.expand_path(config_path)
                   end
            FileUtils.mkdir_p(path)
            path
          rescue StandardError
            fallback = dict_avail&.default_databases_path || File.join(Dir.home, '.local', 'share', 'shoko',
                                                                       'dictionaries')
            FileUtils.mkdir_p(fallback)
            fallback
          end

          def merge_dictionary_installation(remote_items)
            base_path = dictionary_storage_path
            Array(remote_items).filter_map do |item|
              name = item[:name] || item['name']
              next unless name

              path = File.join(base_path, name.to_s)
              installed = File.exist?(path)
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
        end
      end
    end
  end
end
