# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for generic file storage operations.
      # Adapters implementing this interface should handle atomic
      # file writes and reads with proper error handling.
      #
      # @example Implementing this port
      #   class FileStorage
      #     include Shoko::Core::Ports::Storage
      #
      #     def read(path)
      #       # Implementation
      #     end
      #   end
      module Storage
        # Read content from a file
        #
        # @param path [String] File path
        # @return [String, nil] File content, or nil if not found
        def read(path)
          raise NotImplementedError, "#{self.class} must implement #read"
        end

        # Write content to a file atomically
        #
        # @param path [String] File path
        # @param content [String] Content to write
        # @return [Boolean] True if written successfully
        def write(path, content)
          raise NotImplementedError, "#{self.class} must implement #write"
        end

        # Delete a file
        #
        # @param path [String] File path
        # @return [Boolean] True if deleted successfully
        def delete(path)
          raise NotImplementedError, "#{self.class} must implement #delete"
        end

        # Check if a file exists
        #
        # @param path [String] File path
        # @return [Boolean] True if file exists
        def exists?(path)
          raise NotImplementedError, "#{self.class} must implement #exists?"
        end

        # List files in a directory
        #
        # @param path [String] Directory path
        # @param pattern [String] Glob pattern (default: '*')
        # @return [Array<String>] Array of file paths
        def list(path, pattern: '*')
          raise NotImplementedError, "#{self.class} must implement #list"
        end

        # Create directory (including parents)
        #
        # @param path [String] Directory path
        # @return [Boolean] True if created successfully
        def mkdir(path)
          raise NotImplementedError, "#{self.class} must implement #mkdir"
        end

        # Read JSON file
        #
        # @param path [String] File path
        # @return [Hash, Array, nil] Parsed JSON, or nil if not found/invalid
        def read_json(path)
          raise NotImplementedError, "#{self.class} must implement #read_json"
        end

        # Write JSON file atomically
        #
        # @param path [String] File path
        # @param data [Hash, Array] Data to serialize
        # @return [Boolean] True if written successfully
        def write_json(path, data)
          raise NotImplementedError, "#{self.class} must implement #write_json"
        end
      end
    end
  end
end
