# frozen_string_literal: true

require_relative '../../core/ports/outbound/cache_pointer_resolver'
require_relative 'epub_cache'
require_relative 'cache_pointer_manager'

module Shoko
  module Adapters
    module Storage
      # Adapter for resolving EPUB cache pointer files.
      class CachePointerResolver
        include Core::Ports::Outbound::CachePointerResolver
        SourcePathPayload = Struct.new(:source_path)

        def cache_pointer?(path)
          EpubCache.cache_file?(path)
        end

        def read_cache(path, strict: false)
          payload = EpubCache.new(path).read_cache(strict: strict)
          return payload if payload
          return nil if strict

          pointer = CachePointerManager.new(path).read
          source_path = pointer && pointer['source_path'].to_s.strip
          return nil if source_path.nil? || source_path.empty?

          SourcePathPayload.new(source_path)
        rescue Shoko::Error
          raise
        end
      end
    end
  end
end
