# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

require_relative '../../application/ports/outbound/recent_files_repository'
require_relative 'atomic_file_writer'
require_relative 'config_paths'
require_relative '../../shared/text_sanitizer'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Storage
      # Instance-based adapter for recent files persistence.
      class RecentFilesRepository
        include Application::Ports::Outbound::RecentFilesRepository

        MAX_RECENT_FILES = 10

        def self.default_recent_file_path
          File.join(ConfigPaths.config_root, 'recent.json')
        end

        def initialize(recent_file_path:, atomic_file_writer:, wall_clock:, file_utils: FileUtils)
          raise ArgumentError, 'wall_clock must respond to #utc_now' unless wall_clock.respond_to?(:utc_now)

          @recent_file_path = recent_file_path.to_s
          @atomic_file_writer = atomic_file_writer
          @wall_clock = wall_clock
          @file_utils = file_utils
        end

        def add(path)
          cleaned_path = path.to_s.strip
          raise ArgumentError, 'path is required' if cleaned_path.empty?

          recent_files = load.reject { |file| file['path'] == cleaned_path }
          save([new_entry(cleaned_path), *recent_files].first(MAX_RECENT_FILES))
        rescue StandardError => e
          raise_storage_error('recent_files_add', e)
        end

        def load
          return [] unless File.exist?(@recent_file_path)

          entries = JSON.parse(File.read(@recent_file_path))
          validate_entries!(entries).map { |row| sanitize_entry(row) }
        rescue StandardError => e
          raise_storage_error('recent_files_load', e)
        end

        def clear
          @file_utils.rm_f(@recent_file_path)
        rescue StandardError => e
          raise_storage_error('recent_files_clear', e)
        end

        private

        def save(recent)
          @file_utils.mkdir_p(File.dirname(@recent_file_path))
          payload = JSON.pretty_generate(recent)
          @atomic_file_writer.write(@recent_file_path, payload)
        rescue StandardError => e
          raise_storage_error('recent_files_save', e)
        end

        def new_entry(cleaned_path)
          {
            'path' => cleaned_path,
            'name' => sanitized_label(cleaned_path),
            'accessed' => @wall_clock.utc_now.iso8601,
          }
        end

        def sanitized_label(path)
          raw_label = File.basename(path, File.extname(path)).tr('_-', ' ')
          Shoko::Shared::TextSanitizer.sanitize(raw_label, preserve_newlines: false, preserve_tabs: false)
        end

        def sanitize_entry(row)
          safe = row.dup
          safe['name'] = Shoko::Shared::TextSanitizer.sanitize(
            safe['name'].to_s,
            preserve_newlines: false,
            preserve_tabs: false
          )
          safe
        end

        def validate_entries!(entries)
          unless entries.is_a?(Array)
            raise Shoko::StorageError.new('recent_files_load', @recent_file_path, 'expected an array payload')
          end

          entries.each_with_index do |row, idx|
            unless row.is_a?(Hash)
              raise Shoko::StorageError.new('recent_files_load', @recent_file_path, "entry #{idx} is not a hash")
            end

            next if row.key?('path') && row.key?('name') && row.key?('accessed')

            raise Shoko::StorageError.new('recent_files_load', @recent_file_path, "entry #{idx} missing required keys")
          end

          entries
        end

        def raise_storage_error(operation, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::StorageError.new(operation, @recent_file_path, error.message)
        end
      end
    end
  end
end
