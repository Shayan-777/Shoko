# frozen_string_literal: true

require 'fileutils'
require_relative '../../core/ports/outbound/data_cleanup'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Storage
      # Adapter implementing guarded filesystem cleanup operations.
      class DataCleanupAdapter
        include Core::Ports::Outbound::DataCleanup

        def remove_cache_root(cache_root)
          return unless cache_root && File.directory?(cache_root)

          cache_real = safe_realpath!(cache_root, allowed_basenames: %w[shoko reader])
          FileUtils.rm_rf(cache_real)
        rescue StandardError => e
          raise_storage_error('remove_cache_root', cache_root, e)
        end

        def remove_downloads_root(config_root)
          return unless config_root

          downloads_root = File.join(config_root, 'downloads')
          return unless File.directory?(downloads_root)

          downloads_real = safe_realpath!(downloads_root, allowed_basenames: ['downloads'])
          FileUtils.rm_rf(downloads_real)
        rescue StandardError => e
          raise_storage_error('remove_downloads_root', downloads_root, e)
        end

        def remove_user_data_files(config_root:, annotations:, bookmarks:, progress:, config_file:)
          root_path = config_root.to_s
          raise ArgumentError, 'config_root is required' if root_path.strip.empty?
          raise Shoko::StorageError.new('remove_user_data_files', root_path, 'config_root does not exist') unless File.directory?(root_path)

          root_real = safe_realpath!(root_path)

          files = {
            annotations: File.join(root_real, 'annotations.json'),
            bookmarks: File.join(root_real, 'bookmarks.json'),
            progress: File.join(root_real, 'progress.json'),
            config_file: File.join(root_real, 'config.json'),
          }

          FileUtils.rm_f(files[:annotations]) if annotations
          FileUtils.rm_f(files[:bookmarks]) if bookmarks
          FileUtils.rm_f(files[:progress]) if progress
          FileUtils.rm_f(files[:config_file]) if config_file
        rescue StandardError => e
          raise_storage_error('remove_user_data_files', config_root, e)
        end

        private

        def safe_realpath!(path, allowed_basenames: nil)
          real = File.realpath(path)
          raise Shoko::StorageError.new('resolve_realpath', path, 'unsafe target path') if real == '/' || real == Dir.home
          if allowed_basenames && !allowed_basenames.include?(File.basename(real))
            raise Shoko::StorageError.new(
              'resolve_realpath',
              path,
              "unexpected basename '#{File.basename(real)}'"
            )
          end

          real
        rescue StandardError => e
          raise_storage_error('resolve_realpath', path, e)
        end

        def raise_storage_error(operation, path, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::StorageError.new(operation, path.to_s, error.message)
        end
      end
    end
  end
end
