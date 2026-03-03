# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_workflow_runtime'
require_relative '../../../core/ports/outbound/menu_workflow_state_reader'
require_relative '../../../core/ports/outbound/menu_workflow_state_writer'
require_relative '../../../core/models/dictionary_catalog_entry'

module Shoko
  module Application
    module Workflows
      module Menu
        class DictionaryWorkflow
          def initialize(dictionary_catalog_service:, dictionary_storage:, config_reader:, menu_state_reader:,
                         menu_state_writer:, menu_runtime:, clock:, file_probe: nil, path_ops: nil, logger: nil)
            raise ArgumentError, 'dictionary_catalog_service is required' if dictionary_catalog_service.nil?
            raise ArgumentError, 'dictionary_storage is required' if dictionary_storage.nil?
            @dictionary_catalog_service = dictionary_catalog_service
            @dictionary_storage = dictionary_storage
            @config_reader = config_reader
            unless menu_state_reader.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateReader)
              raise ArgumentError, 'menu_state_reader must implement Core::Ports::Outbound::MenuWorkflowStateReader'
            end
            unless menu_state_writer.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
              raise ArgumentError, 'menu_state_writer must implement Core::Ports::Outbound::MenuWorkflowStateWriter'
            end
            @menu_state_reader = menu_state_reader
            @menu_state_writer = menu_state_writer
            raise ArgumentError, 'menu_runtime is required' if menu_runtime.nil?
            unless menu_runtime.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowRuntime)
              raise ArgumentError, 'menu_runtime must implement Core::Ports::Outbound::MenuWorkflowRuntime'
            end

            @menu_runtime = menu_runtime
            @file_probe = file_probe
            @path_ops = path_ops
            @logger = logger
            raise ArgumentError, 'clock is required' if clock.nil?

            @clock = clock
          end

          def fetch_dictionary_catalog
            update_dictionary_state(dictionary_status: :loading,
                                    dictionary_message: 'Loading dictionary list...',
                                    dictionary_progress: 0.0,
                                    dictionary_results: [],
                                    dictionary_selected: 0)
            draw_screen

            remote_items = @dictionary_catalog_service.list_remote
            results = merge_dictionary_installation(remote_items)
            update_dictionary_state(dictionary_status: :done,
                                    dictionary_message: "Found #{results.length} dictionaries",
                                    dictionary_progress: 0.0,
                                    dictionary_results: results,
                                    dictionary_selected: 0)
          rescue Shoko::FatalExternalInputError
            raise
          # resilient-boundary
          rescue Shoko::Error => e
            log_resilient('fetch_dictionary_catalog', e)
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Catalog failed: #{e.message}",
                                    dictionary_progress: 0.0)
          ensure
            draw_screen
          end

          def download_dictionary(entry)
            return unless entry
            name = 'dictionary'

            selected_entry = coerce_catalog_entry(entry)
            name = selected_entry.name
            update_dictionary_state(dictionary_status: :downloading,
                                    dictionary_message: "Downloading #{name}...",
                                    dictionary_progress: 0.0)
            draw_screen

            last_draw = monotonic_now
            dest_dir = dictionary_storage_path
            result = normalize_download_result(@dictionary_catalog_service.download(selected_entry.to_download_h, dest_dir) do |done, total|
              progress = total.to_i.positive? ? done.to_f / total : 0.0
              now = monotonic_now
              next if (now - last_draw) < 0.08 && progress < 1.0

              percent = total.to_i.positive? ? (progress * 100).round : nil
              message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
              update_dictionary_state(dictionary_progress: progress, dictionary_message: message)
              draw_screen
              last_draw = now
            end)

            message = result[:existing] ? 'Already installed' : "Saved to #{path_basename(result[:path])}"
            update_dictionary_state(dictionary_status: :done,
                                    dictionary_message: message,
                                    dictionary_progress: 0.0)
            mark_dictionary_installed(result[:path]) if result[:path]
          rescue Shoko::FatalExternalInputError
            raise
          # resilient-boundary
          rescue Shoko::Error => e
            log_resilient('download_dictionary', e, entry_name: name.to_s)
            update_dictionary_state(dictionary_status: :error,
                                    dictionary_message: "Download failed: #{e.message}",
                                    dictionary_progress: 0.0)
          ensure
            draw_screen
          end

          private

          def update_dictionary_state(payload)
            @menu_state_writer.set_dictionary_state(payload)
          end

          def dictionary_storage_path
            @dictionary_storage&.ensure_databases_path(@config_reader.dictionary_path)
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
            results = Array(@menu_state_reader.dictionary_entries).map { |entry| coerce_catalog_entry(entry) }
            return if results.empty?

            updated = results.map do |item|
              next item unless item.path.to_s == path.to_s

              item.with_installation(installed: true, path: path)
            end
            update_dictionary_state(dictionary_results: updated.map(&:to_h))
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
        end
      end
    end
  end
end
