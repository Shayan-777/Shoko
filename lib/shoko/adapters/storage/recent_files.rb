# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require_relative 'atomic_file_writer'
require_relative 'config_paths'
require_relative '../../shared/text_sanitizer'

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
            recent_files = load.reject { |file| file['path'] == path }

            raw_label = File.basename(path, File.extname(path)).tr('_-', ' ')
            label = Shoko::Shared::TextSanitizer.sanitize(raw_label, preserve_newlines: false,
                                                                     preserve_tabs: false)

            new_entry = {
              'path' => path,
              'name' => label,
              'accessed' => Time.now.iso8601,
            }

            save([new_entry, *recent_files].first(MAX_RECENT_FILES))
          end

          # Loads the list of recent files from disk.
          #
          # @return [Array<Hash>] An array of recent file entries.
          def load
            return [] unless File.exist?(RECENT_FILE)

            entries = JSON.parse(File.read(RECENT_FILE))
            Array(entries).map do |row|
              next row unless row.is_a?(Hash)

              safe = row.dup
              safe['name'] =
                Shoko::Shared::TextSanitizer.sanitize(safe['name'].to_s,
                                                         preserve_newlines: false, preserve_tabs: false)
              safe
            end
          end

          # Clears the recent files list by removing the recent file.
          def clear
            FileUtils.rm_f(RECENT_FILE)
          rescue Errno::EACCES, Errno::ENOENT
            # Ignore errors
          end

          private

          # Saves the list of recent files to disk.
          #
          # @param recent [Array<Hash>] The list of recent files to save.
          def save(recent)
            FileUtils.mkdir_p(File.dirname(RECENT_FILE))
            payload = JSON.pretty_generate(recent)
            Shoko::Adapters::Storage::AtomicFileWriter.write(RECENT_FILE, payload)
          end
        end
      end
    end
  end
end
