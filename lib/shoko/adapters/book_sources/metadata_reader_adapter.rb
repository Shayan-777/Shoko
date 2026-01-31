# frozen_string_literal: true

require_relative '../../core/ports/metadata_reader'

module Shoko
  module Adapters::BookSources
    # Adapter implementing the MetadataReader port.
    # Metadata extraction strategy is injected to avoid coupling to a specific parser.
    class MetadataReaderAdapter
      include Core::Ports::MetadataReader

      def initialize(extractor:)
        @extractor = extractor
      end

      def extract_metadata(path)
        @extractor.from_epub(path)
      end
    end
  end
end
