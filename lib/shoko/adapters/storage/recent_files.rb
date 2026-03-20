# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require_relative 'atomic_file_writer'
require_relative 'config_paths'
require_relative '../../shared/text_sanitizer'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Storage
      # Manages a list of recently opened files.
      class RecentFiles
        CONFIG_DIR = Adapters::Storage::ConfigPaths.config_root
        RECENT_FILE = File.join(CONFIG_DIR, 'recent.json')
        MAX_RECENT_FILES = 10

        class << self
          # Adds a file path to the top of the recent files list.
          #
          # @param path [String] The path to the file to add.
          def add(path)
            cleaned_path = path.to_s.strip
            raise ArgumentError, 'path is required' if cleaned_path.empty?

            recent_files = load.reject { |file| file['path'] == cleaned_path }

            raw_label = File.basename(cleaned_path, File.extname(cleaned_path)).tr('_-', ' ')
            label = Shoko::Shared::TextSanitizer.sanitize(raw_label, preserve_newlines: false, preserve_tabs: false)

            new_entry = { 'path' => cleaned_path, 'name' => label, 'accessed' => Time.now.iso8601 }

            save([new_entry, *recent_files].first(MAX_RECENT_FILES))
          rescue StandardError => e
            raise_storage_error('recent_files_add', RECENT_FILE, e)
          end

          # Loads the list of recent files from disk.
          #
          # @return [Array<Hash>] An array of recent file entries.
          def load
            return [] unless File.exist?(RECENT_FILE)

            entries = JSON.parse(File.read(RECENT_FILE))
            rows = validate_entries!(entries)
            rows.map do |row|
              next row unless row.is_a?(Hash)

              safe = row.dup
              safe['name'] =
                Shoko::Shared::TextSanitizer.sanitize(safe['name'].to_s,
                                                      preserve_newlines: false,
                                                      preserve_tabs: false)
              safe
            end
          rescue StandardError => e
            raise_storage_error('recent_files_load', RECENT_FILE, e)
          end

          # Clears the recent files list by removing the recent file.
          def clear
            FileUtils.rm_f(RECENT_FILE)
          rescue StandardError => e
            raise_storage_error('recent_files_clear', RECENT_FILE, e)
          end

          private

          # Saves the list of recent files to disk.
          #
          # @param recent [Array<Hash>] The list of recent files to save.
          def save(recent)
            FileUtils.mkdir_p(File.dirname(RECENT_FILE))
            payload = JSON.pretty_generate(recent)
            Shoko::Adapters::Storage::AtomicFileWriter.write(RECENT_FILE, payload)
          rescue StandardError => e
            raise_storage_error('recent_files_save', RECENT_FILE, e)
          end

          def validate_entries!(entries)
            unless entries.is_a?(Array)
              raise Shoko::StorageError.new('recent_files_load', RECENT_FILE, 'expected an array payload')
            end

            entries.each_with_index do |row, idx|
              unless row.is_a?(Hash)
                raise Shoko::StorageError.new('recent_files_load', RECENT_FILE, "entry #{idx} is not a hash")
              end

              next if row.key?('path') && row.key?('name') && row.key?('accessed')

              raise Shoko::StorageError.new('recent_files_load', RECENT_FILE, "entry #{idx} missing required keys")
            end

            entries
          end

          def raise_storage_error(operation, path, error)
            raise error if error.is_a?(Shoko::Error)

            raise Shoko::StorageError.new(operation, path.to_s, error.message)
          end
        end
      end
    end
  end
end
