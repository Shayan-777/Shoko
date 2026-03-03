# frozen_string_literal: true

require_relative '../ports/outbound/cache_pointer_resolver'
require_relative '../ports/outbound/path_ops'
require_relative '../ports/outbound/reader_document'

module Shoko
  module Core
    module Services
      # Resolves canonical reader document paths and source/cache-pointer matching.
      class DocumentPathResolver
        def initialize(cache_pointer_resolver:, path_ops:, logger: nil)
          raise ArgumentError, 'cache_pointer_resolver is required' if cache_pointer_resolver.nil?
          unless cache_pointer_resolver.is_a?(Shoko::Core::Ports::Outbound::CachePointerResolver)
            raise ArgumentError, 'cache_pointer_resolver must implement Core::Ports::Outbound::CachePointerResolver'
          end
          raise ArgumentError, 'path_ops is required' if path_ops.nil?
          unless path_ops.is_a?(Shoko::Core::Ports::Outbound::PathOps)
            raise ArgumentError, 'path_ops must implement Core::Ports::Outbound::PathOps'
          end

          @cache_pointer_resolver = cache_pointer_resolver
          @path_ops = path_ops
          @logger = logger
        end

        def canonical_reader_path(path)
          return nil unless path

          canonical = resolve_source_path(path)
          safe_expand_path(canonical)
        end

        def document_matches_path?(document, target_path)
          return false unless document && target_path
          unless document.is_a?(Shoko::Core::Ports::Outbound::ReaderDocument)
            raise ArgumentError, 'document must implement Core::Ports::Outbound::ReaderDocument'
          end

          doc_path = document.canonical_path
          return false unless doc_path

          safe_expand_path(doc_path) == safe_expand_path(target_path)
        end

        def resolve_source_path(path)
          return path unless @cache_pointer_resolver.cache_pointer?(path)

          payload = @cache_pointer_resolver.read_cache(path, strict: false)
          source = payload&.source_path
          source && !source.empty? ? source : path
        end

        private

        def safe_expand_path(path)
          @path_ops.expand_path(path).to_s
        end
      end
    end
  end
end
