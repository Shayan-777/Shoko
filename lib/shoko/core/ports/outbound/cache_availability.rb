# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for checking cache availability for a source path.
      module CacheAvailability
        # Determine if a valid cache is available for the given source path.
        #
        # @param path [String]
        # @return [Boolean]
        def cache_available?(path)
          raise NotImplementedError, "#{self.class} must implement #cache_available?"
        end
      end
    end
  end
end
