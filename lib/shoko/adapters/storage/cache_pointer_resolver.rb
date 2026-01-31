# frozen_string_literal: true

require_relative '../../core/ports/cache_pointer_resolver'
require_relative 'epub_cache'

module Shoko
  module Adapters
    module Storage
      # Adapter for resolving EPUB cache pointer files.
      class CachePointerResolver
        include Core::Ports::CachePointerResolver

        def cache_pointer?(path)
          EpubCache.cache_file?(path)
        end

        def read_cache(path, strict: false)
          EpubCache.new(path).read_cache(strict: strict)
        rescue StandardError
          nil
        end
      end
    end
  end
end
