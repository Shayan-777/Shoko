# frozen_string_literal: true

require_relative '../../core/ports/outbound/folder_importer'
require_relative '../../core/ports/outbound/document_loader'

module Shoko
  module Adapters
    module BookSources
      # Imports a document into cache through the existing document service pipeline.
      class CacheImportAdapter
        include Shoko::Core::Ports::Outbound::FolderImporter

        def initialize(document_loader:)
          unless document_loader.is_a?(Shoko::Core::Ports::Outbound::DocumentLoader)
            raise ArgumentError, 'document_loader must implement Core::Ports::Outbound::DocumentLoader'
          end

          @document_loader = document_loader
        end

        def import(path)
          document = @document_loader.load(path: path, progress_reporter: nil, background_worker: nil)
          raise Shoko::BookParseError.new('document import returned nil', path) unless document

          document.cached? ? :skipped : :imported
        end
      end
    end
  end
end
