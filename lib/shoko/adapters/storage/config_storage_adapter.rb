# frozen_string_literal: true

require 'fileutils'
require_relative '../../core/ports/config_storage'
require_relative 'config_paths'
require_relative 'atomic_file_writer'

module Shoko
  module Adapters
    module Storage
      # Adapter implementing the ConfigStorage port.
      # Wraps ConfigPaths for path resolution and AtomicFileWriter for persistence.
      class ConfigStorageAdapter
        include Core::Ports::ConfigStorage

        # Get the configuration directory path.
        #
        # @return [String] Absolute path to config directory
        def config_dir
          ConfigPaths.config_root
        end

        # Get the configuration file path.
        #
        # @param filename [String] Config filename (default: 'config.json')
        # @return [String] Absolute path to config file
        def config_file(filename = 'config.json')
          ConfigPaths.config_path(filename)
        end

        # Ensure the configuration directory exists.
        #
        # @return [Boolean] True if directory exists or was created
        def ensure_config_dir
          FileUtils.mkdir_p(config_dir)
          true
        rescue StandardError
          false
        end

        # Write data atomically to a file path.
        #
        # @param path [String] File path to write to
        # @param data [String] Content to write
        # @return [Boolean] True if written successfully
        def atomic_write(path, data)
          AtomicFileWriter.write(path, data)
          true
        rescue StandardError
          false
        end

        # Read content from a file path.
        #
        # @param path [String] File path to read from
        # @return [String, nil] File content, or nil if not found
        def read_file(path)
          return nil unless File.exist?(path)

          File.read(path)
        rescue StandardError
          nil
        end
      end
    end
  end
end
