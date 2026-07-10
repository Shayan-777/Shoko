# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

require_relative '../../application/ports/outbound/recent_files_repository'
require_relative 'atomic_file_writer'
require_relative 'config_paths'
require_relative 'repositories/storage/file_store_utils'
require_relative '../../shared/text_sanitizer'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Storage
      # Instance-based adapter for recent files persistence.
      #
      # Recent history is an ancillary sidecar, so it follows the same failure
      # discipline as the annotation/bookmark/progress stores: reads degrade to
      # empty (content corruption is quarantined first so the history stays
      # recoverable), while mutations run their whole read-modify-write under
      # the sidecar flock and abort on access errors — a transiently unreadable
      # file must never be flattened to a one-entry baseline by the next save.
      class RecentFilesRepository
        include Application::Ports::Outbound::RecentFilesRepository

        MAX_RECENT_FILES = 10

        def self.default_recent_file_path
          File.join(ConfigPaths.config_root, 'recent.json')
        end

        def initialize(recent_file_path:, atomic_file_writer:, wall_clock:, file_utils: FileUtils, logger: nil)
          raise ArgumentError, 'wall_clock must respond to #utc_now' unless wall_clock.respond_to?(:utc_now)

          @recent_file_path = recent_file_path.to_s
          @atomic_file_writer = atomic_file_writer
          @wall_clock = wall_clock
          @file_utils = file_utils
          @logger = logger
        end

        def add(path)
          cleaned_path = path.to_s.strip
          raise ArgumentError, 'path is required' if cleaned_path.empty?

          entry = new_entry(cleaned_path)
          Repositories::Storage::FileStoreUtils.with_update_lock(@recent_file_path) do
            recent_files = load_for_update.reject { |file| file['path'] == cleaned_path }
            save([entry, *recent_files].first(MAX_RECENT_FILES))
          end
        rescue StandardError => e
          raise_storage_error('recent_files_add', e)
        end

        # Reads never raise: an unusable recent.json costs the recent list,
        # not the menu or a book launch.
        def load
          read_valid_entries
        rescue SystemCallError, IOError
          []
        end

        def clear
          @file_utils.rm_f(@recent_file_path)
        rescue StandardError => e
          raise_storage_error('recent_files_clear', e)
        end

        private

        # Mutation-time baseline read: access errors abort the mutation.
        def load_for_update
          read_valid_entries
        rescue SystemCallError, IOError => e
          raise Shoko::StorageError.new('recent_files_load', @recent_file_path, e.message)
        end

        # Parses and validates the stored entries. Content corruption —
        # unparseable JSON or a wrong-shape payload — is quarantined (the file
        # still holds user history worth recovering) and reads as empty, so the
        # next add writes a clean file. Access errors propagate to the caller,
        # which decides whether to degrade (read) or abort (mutation).
        def read_valid_entries
          return [] unless File.exist?(@recent_file_path)

          entries = JSON.parse(File.read(@recent_file_path))
          validate_entries!(entries).map { |row| sanitize_entry(row) }
        rescue JSON::ParserError, Shoko::StorageError => e
          Repositories::Storage::FileStoreUtils.quarantine_corrupt_file(@recent_file_path, @logger, reason: e.message)
          []
        end

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
