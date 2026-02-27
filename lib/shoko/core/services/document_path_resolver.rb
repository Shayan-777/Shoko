# frozen_string_literal: true

require_relative '../ports/outbound/cache_pointer_resolver'
require_relative '../ports/outbound/path_ops'

module Shoko
  module Core
    module Services
      # Resolves canonical reader document paths and source/cache-pointer matching.
      class DocumentPathResolver
        def initialize(cache_pointer_resolver:, path_ops:, logger: nil)
          @cache_pointer_resolver = cache_pointer_resolver
          @path_ops = path_ops
          @logger = logger
        end

        def canonical_reader_path(path)
          return nil unless path

          canonical = resolve_source_path(path)
          safe_expand_path(canonical)
        rescue StandardError => e
          @logger&.debug("DocumentPathResolver.canonical_reader_path failed: #{e.message}")
          path
        end

        def document_matches_path?(document, target_path)
          return false unless document && target_path

          doc_path = if document.respond_to?(:canonical_path)
                       document.canonical_path
                     elsif document.respond_to?(:source_path)
                       document.source_path
                     elsif document.respond_to?(:path)
                       document.path
                     end
          return false unless doc_path

          safe_expand_path(doc_path) == safe_expand_path(target_path)
        rescue StandardError => e
          @logger&.debug("DocumentPathResolver.document_matches_path? failed: #{e.message}")
          false
        end

        def resolve_source_path(path)
          return path unless @cache_pointer_resolver&.cache_pointer?(path)

          payload = @cache_pointer_resolver.read_cache(path, strict: false)
          source = payload&.source_path
          source && !source.empty? ? source : path
        rescue StandardError => e
          @logger&.debug("DocumentPathResolver.resolve_source_path failed: #{e.message}")
          path
        end

        private

        def safe_expand_path(path)
          return path.to_s unless @path_ops&.respond_to?(:expand_path)

          @path_ops.expand_path(path).to_s
        rescue StandardError
          path.to_s
        end
      end
    end
  end
end
