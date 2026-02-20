# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for configuration storage operations.
      # Abstracts the persistence of application configuration,
      # hiding XDG paths and atomic file writing from the application layer.
      #
      # @example Implementing this port
      #   class ConfigStorageAdapter
      #     include Shoko::Core::Ports::ConfigStorage
      #
      #     def config_dir
      #       File.join(ENV.fetch('XDG_CONFIG_HOME', '~/.config'), 'shoko')
      #     end
      #   end
      module ConfigStorage
        # Get the configuration directory path.
        #
        # @return [String] Absolute path to config directory
        def config_dir
          raise NotImplementedError, "#{self.class} must implement #config_dir"
        end

        # Get the configuration file path.
        #
        # @param filename [String] Config filename (default: 'config.json')
        # @return [String] Absolute path to config file
        def config_file(filename = 'config.json')
          raise NotImplementedError, "#{self.class} must implement #config_file"
        end

        # Ensure the configuration directory exists.
        #
        # @return [Boolean] True if directory exists or was created
        def ensure_config_dir
          raise NotImplementedError, "#{self.class} must implement #ensure_config_dir"
        end

        # Write data atomically to a file path.
        # Uses temp file + rename pattern to prevent corruption.
        #
        # @param path [String] File path to write to
        # @param data [String] Content to write
        # @return [Boolean] True if written successfully
        def atomic_write(path, data)
          raise NotImplementedError, "#{self.class} must implement #atomic_write"
        end

        # Read content from a file path.
        #
        # @param path [String] File path to read from
        # @return [String, nil] File content, or nil if not found
        def read_file(path)
          raise NotImplementedError, "#{self.class} must implement #read_file"
        end
      end
    end
  end
end
