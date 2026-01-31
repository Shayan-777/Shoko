# frozen_string_literal: true

require_relative '../../core/ports/cache_pointer_resolver'

module Shoko
  module Application::Controllers
    # Shared logic for resolving canonical document paths and matching
    # documents to file paths. Used by both Menu::StateController and
    # ReaderController to avoid duplicated implementations that can
    # drift out of sync.
    module DocumentPathResolver
      def canonical_reader_path(path)
        return nil unless path

        canonical = resolve_source_path(path)
        File.expand_path(canonical)
      rescue StandardError => e
        document_path_logger&.debug("DocumentPathResolver.canonical_reader_path failed: #{e.message}")
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

        File.expand_path(doc_path) == File.expand_path(target_path)
      rescue StandardError => e
        document_path_logger&.debug("DocumentPathResolver.document_matches_path? failed: #{e.message}")
        false
      end

      private

      def resolve_source_path(path)
        resolver = cache_pointer_resolver
        return path unless resolver&.cache_pointer?(path)

        payload = resolver.read_cache(path, strict: false)
        source = payload&.source_path
        source && !source.empty? ? source : path
      rescue StandardError => e
        document_path_logger&.debug("DocumentPathResolver.resolve_source_path failed: #{e.message}")
        path
      end

      # Host classes should set @cache_pointer_resolver in their constructor.
      def cache_pointer_resolver
        return @cache_pointer_resolver if defined?(@cache_pointer_resolver) && @cache_pointer_resolver

        nil
      end

      # Host classes should set @logger in their constructor.
      def document_path_logger
        return @logger if defined?(@logger) && @logger

        nil
      end
    end
  end
end
