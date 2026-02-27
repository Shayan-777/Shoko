# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for resolving cache pointer files to source metadata.
        module CachePointerResolver
          # Determine if the given path is a cache pointer file.
          #
          # @param path [String]
          # @return [Boolean]
          def cache_pointer?(path)
            raise NotImplementedError, "#{self.class} must implement #cache_pointer?"
          end

          # Read the cache payload for a pointer file.
          #
          # @param path [String]
          # @param strict [Boolean]
          # @return [Object, nil]
          def read_cache(path, strict: false)
            raise NotImplementedError, "#{self.class} must implement #read_cache"
          end
        end
      end
    end
  end
end
