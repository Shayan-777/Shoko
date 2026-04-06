# frozen_string_literal: true

require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/menu_session_store'
require_relative '../../../core/ports/outbound/menu_transient_store'
require_relative '../../../core/models/dictionary_catalog_entry'
require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/models/session/menu_state_partition'
require_relative 'menu_state_persistence'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side dictionary catalog loading and installation state.
        class DictionaryWorkflow
          MIN_PROGRESS_DELTA = 0.01
          include MenuStatePersistence

          def initialize(dictionary_catalog_service:, dictionary_storage:, app_config_store:, menu_session_store:,
                         menu_transient_store:, file_probe: nil, path_ops: nil, logger: nil)
            raise ArgumentError, 'dictionary_catalog_service is required' if dictionary_catalog_service.nil?
            raise ArgumentError, 'dictionary_storage is required' if dictionary_storage.nil?
            unless app_config_store.is_a?(Shoko::Core::Ports::Outbound::AppConfigStore)
              raise ArgumentError, 'app_config_store must implement Core::Ports::Outbound::AppConfigStore'
            end
            unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
              raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
            end
            unless menu_transient_store.is_a?(Shoko::Core::Ports::Outbound::MenuTransientStore)
              raise ArgumentError, 'menu_transient_store must implement Core::Ports::Outbound::MenuTransientStore'
            end

            @dictionary_catalog_service = dictionary_catalog_service
            @dictionary_storage = dictionary_storage
            @app_config_store = app_config_store
            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
            @file_probe = file_probe
            @path_ops = path_ops
            @logger = logger
          end

          def fetch_dictionary_catalog
            update_dictionary_state(dictionary_catalog_started_payload)
            remote_items = @dictionary_catalog_service.list_remote
            results = merge_dictionary_installation(remote_items)
            update_dictionary_state(dictionary_catalog_result_payload(results))
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('fetch_dictionary_catalog', e)
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Catalog failed: #{e.message}",
                                    dictionary_progress: 0.0)
          end

          def download_dictionary(entry)
            return unless entry

            name = 'dictionary'
            selected_entry = coerce_catalog_entry(entry)
            name = selected_entry.name
            update_dictionary_state(dictionary_download_started_payload(name))
            result = normalized_dictionary_download(selected_entry, name)

            update_dictionary_state(dictionary_download_completed_payload(result))
            mark_dictionary_installed(result[:path]) if result[:path]
          rescue Shoko::Error => e
            raise if e.is_a?(Shoko::FatalExternalInputError)

            log_resilient('download_dictionary', e, entry_name: name.to_s)
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Download failed: #{e.message}",
                                    dictionary_progress: 0.0)
          end

          private

          def update_dictionary_state(payload)
            persist_menu_payload(payload)
          end

          def dictionary_storage_path
            @dictionary_storage&.ensure_databases_path(current_config.dictionary_path)
          end

          def merge_dictionary_installation(remote_items)
            base_path = dictionary_storage_path
            Array(remote_items).filter_map do |item|
              entry = coerce_catalog_entry(item)
              path = join_path(base_path, entry.name)
              installed = file_exists?(path)
              entry.with_installation(installed: installed, path: path).to_h
            end
          end

          def mark_dictionary_installed(path)
            results = Array(current_menu.dictionary_results).map { |entry| coerce_catalog_entry(entry) }
            return if results.empty?

            updated = results.map do |item|
              next item unless item.path.to_s == path.to_s

              item.with_installation(installed: true, path: path)
            end
            update_dictionary_state(dictionary_results: updated.map(&:to_h))
          end

          def current_config
            @app_config_store.load
          end

          def dictionary_catalog_started_payload
            {
              dictionary_status: :loading,
              dictionary_message: 'Loading dictionary list...',
              dictionary_progress: 0.0,
              dictionary_results: [],
              dictionary_selected: 0,
            }
          end

          def dictionary_catalog_result_payload(results)
            {
              dictionary_status: :done,
              dictionary_message: "Found #{results.length} dictionaries",
              dictionary_progress: 0.0,
              dictionary_results: results,
              dictionary_selected: 0,
            }
          end

          def dictionary_download_started_payload(name)
            {
              dictionary_status: :downloading,
              dictionary_message: "Downloading #{name}...",
              dictionary_progress: 0.0,
            }
          end

          def normalized_dictionary_download(selected_entry, name)
            dest_dir = dictionary_storage_path
            normalize_download_result(download_dictionary_entry(selected_entry, dest_dir, name))
          end

          def download_dictionary_entry(selected_entry, dest_dir, name)
            last_progress = nil
            @dictionary_catalog_service.download(selected_entry.to_download_h, dest_dir) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              next unless publish_progress?(progress, last_progress)

              update_dictionary_state(dictionary_progress_payload(name, progress, total))
              last_progress = progress
            end
          end

          def dictionary_progress_payload(name, progress, total)
            percent = total.to_i.positive? ? (progress * 100).round : nil
            message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
            { dictionary_progress: progress, dictionary_message: message }
          end

          def dictionary_download_completed_payload(result)
            {
              dictionary_status: :done,
              dictionary_message: dictionary_download_result_message(result),
              dictionary_progress: 0.0,
            }
          end

          def dictionary_download_result_message(result)
            result[:existing] ? 'Already installed' : "Saved to #{path_basename(result[:path])}"
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

          def log_resilient(operation, error, **metadata)
            @logger&.error(
              "menu.dictionary_workflow.#{operation}_failed",
              error: error.class.name,
              message: error.message,
              **metadata
            )
          end

          def coerce_catalog_entry(value)
            return value if value.is_a?(Shoko::Core::Models::DictionaryCatalogEntry)

            Shoko::Core::Models::DictionaryCatalogEntry.from_h(value)
          rescue ArgumentError, TypeError => e
            raise Shoko::MalformedDictionaryInputError, e.message
          end

          def normalize_download_result(value)
            unless value.is_a?(Hash)
              raise Shoko::MalformedDictionaryInputError, "download result must be a Hash, got #{value.class}"
            end

            normalized = value.each_with_object({}) do |(key, item), acc|
              normalized_key = key.is_a?(String) ? key.to_sym : key
              acc[normalized_key] = item
            end
            unless normalized.key?(:path) && normalized.key?(:existing)
              raise Shoko::MalformedDictionaryInputError, 'download result missing required keys (:path, :existing)'
            end

            normalized
          end

          def publish_progress?(progress, last_progress)
            return true if last_progress.nil?
            return true if progress >= 1.0

            (progress - last_progress).abs >= MIN_PROGRESS_DELTA
          end
        end
      end
    end
  end
end
