# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      # Imports a document into cache through the existing document service pipeline.
      class CacheImportAdapter
        class ImportError < StandardError; end

        def initialize(document_service_factory:)
          raise ArgumentError, 'document_service_factory is required' unless document_service_factory&.respond_to?(:call)

          @document_service_factory = document_service_factory
        end

        def import(path)
          service = @document_service_factory.call(path, progress_reporter: nil, background_worker: nil)
          document = service.load_document
          raise ImportError, 'Document import returned nil' unless document

          if error_document?(document)
            message = document.error_message.to_s.strip
            raise ImportError, (message.empty? ? 'Document import failed' : message)
          end

          document.respond_to?(:cached?) && document.cached? ? :skipped : :imported
        end

        private

        def error_document?(document)
          return false unless defined?(Shoko::Adapters::BookSources::ErrorDocument)

          document.is_a?(Shoko::Adapters::BookSources::ErrorDocument)
        end
      end
    end
  end
end
