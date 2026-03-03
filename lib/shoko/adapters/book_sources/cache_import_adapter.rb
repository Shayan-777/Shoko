# frozen_string_literal: true

require_relative '../../core/ports/outbound/folder_importer'

module Shoko
  module Adapters
    module BookSources
      # Imports a document into cache through the existing document service pipeline.
      class CacheImportAdapter
        include Shoko::Core::Ports::Outbound::FolderImporter

        class ImportError < StandardError; end

        def initialize(document_service_factory:)
          raise ArgumentError, 'document_service_factory is required' unless document_service_factory&.respond_to?(:call)

          @document_service_factory = document_service_factory
        end

        def import(path)
          service = @document_service_factory.call(path, progress_reporter: nil, background_worker: nil)
          document = service.load_document
          raise ImportError, 'Document import returned nil' unless document

          document.cached? ? :skipped : :imported
        rescue Shoko::BookParseError => e
          raise ImportError, e.message
        end
      end
    end
  end
end
