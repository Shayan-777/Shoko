# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for caching operations.
      # Adapters implementing this interface should handle caching
      # of parsed book data and pagination layouts.
      #
      # @example Implementing this port
      #   class FileCache
      #     include Shoko::Core::Ports::Cache
      #
      #     def read(key)
      #       # Implementation
      #     end
      #   end
      module Cache
        # Read cached data by key
        #
        # @param key [String] Cache key
        # @return [Object, nil] Cached data, or nil if not found
        def read(key)
          raise NotImplementedError, "#{self.class} must implement #read"
        end

        # Write data to cache
        #
        # @param key [String] Cache key
        # @param data [Object] Data to cache
        # @return [Boolean] True if written successfully
        def write(key, data)
          raise NotImplementedError, "#{self.class} must implement #write"
        end

        # Check if cache entry exists
        #
        # @param key [String] Cache key
        # @return [Boolean] True if entry exists
        def exists?(key)
          raise NotImplementedError, "#{self.class} must implement #exists?"
        end

        # Delete cache entry
        #
        # @param key [String] Cache key
        # @return [Boolean] True if deleted successfully
        def delete(key)
          raise NotImplementedError, "#{self.class} must implement #delete"
        end

        # Clear all cache entries
        #
        # @return [Boolean] True if cleared successfully
        def clear
          raise NotImplementedError, "#{self.class} must implement #clear"
        end

        # Get all cache keys
        #
        # @return [Array<String>] Array of cache keys
        def keys
          raise NotImplementedError, "#{self.class} must implement #keys"
        end

        # Check if cache is valid for a source file
        #
        # @param key [String] Cache key
        # @param source_path [String] Path to source file
        # @return [Boolean] True if cache is still valid
        def valid_for_source?(key, source_path)
          raise NotImplementedError, "#{self.class} must implement #valid_for_source?"
        end
      end
    end
  end
end
