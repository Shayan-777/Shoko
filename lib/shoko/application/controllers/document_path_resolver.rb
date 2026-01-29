# frozen_string_literal: true

require_relative '../../adapters/storage/epub_cache'

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
        Shoko::Adapters::Monitoring::Logger.debug("DocumentPathResolver.canonical_reader_path failed: #{e.message}")
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
        Shoko::Adapters::Monitoring::Logger.debug("DocumentPathResolver.document_matches_path? failed: #{e.message}")
        false
      end

      private

      def resolve_source_path(path)
        return path unless Adapters::Storage::EpubCache.cache_file?(path)

        payload = Adapters::Storage::EpubCache.new(path).read_cache(strict: false)
        source = payload&.source_path
        source && !source.empty? ? source : path
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("DocumentPathResolver.resolve_source_path failed: #{e.message}")
        path
      end
    end
  end
end
