# frozen_string_literal: true

require 'fileutils'
require_relative '../../core/ports/outbound/data_cleanup'

module Shoko
  module Adapters
    module Storage
      # Adapter implementing guarded filesystem cleanup operations.
      class DataCleanupAdapter
        include Core::Ports::Outbound::DataCleanup

        def remove_cache_root(cache_root)
          return unless cache_root && File.directory?(cache_root)

          cache_real = safe_realpath(cache_root, allowed_basenames: %w[shoko reader], strict: false)
          return unless cache_real

          FileUtils.rm_rf(cache_real)
        rescue Shoko::Error
          nil
        end

        def remove_downloads_root(config_root)
          return unless config_root

          downloads_root = File.join(config_root, 'downloads')
          return unless File.directory?(downloads_root)

          downloads_real = safe_realpath(downloads_root, allowed_basenames: ['downloads'])
          return unless downloads_real

          FileUtils.rm_rf(downloads_real)
        rescue Shoko::Error
          nil
        end

        def remove_user_data_files(config_root:, annotations:, bookmarks:, progress:, config_file:)
          root_real = safe_realpath(config_root)
          return unless root_real

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
        rescue Shoko::Error
          nil
        end

        private

        def safe_realpath(path, allowed_basenames: nil, strict: true)
          return nil unless path

          real = File.realpath(path)
          return nil if real == '/' || real == Dir.home
          return nil if allowed_basenames && !allowed_basenames.include?(File.basename(real))

          real
        rescue Shoko::Error
          return nil if strict
          return nil unless File.exist?(path)

          real = File.expand_path(path)
          return nil if real == '/' || real == Dir.home
          return nil if allowed_basenames && !allowed_basenames.include?(File.basename(real))

          real
        end
      end
    end
  end
end
