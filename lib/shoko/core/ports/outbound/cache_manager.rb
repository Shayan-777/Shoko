# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for managing application caches.
        # Adapters implementing this interface should handle clearing
        # EPUB and pagination caches and providing cache location paths.
        module CacheManager
          # Clear all cached EPUB data (in-memory and library scan cache)
          #
          # @return [void]
          def clear_epub_cache
            raise NotImplementedError, "#{self.class} must implement #clear_epub_cache"
          end

          # Get the root directory path for cached data on disk
          #
          # @return [String, nil] Cache root directory path
          def cache_root
            raise NotImplementedError, "#{self.class} must implement #cache_root"
          end
        end
      end
    end
  end
end
