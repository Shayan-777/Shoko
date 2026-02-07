# frozen_string_literal: true

require_relative '../../core/ports/metadata_reader'
require_relative 'format_registry'

module Shoko
  module Adapters::BookSources
    # Adapter implementing the MetadataReader port.
    # Uses FormatRegistry to dispatch to the correct metadata extractor
    # based on file extension, with a fallback extractor for legacy usage.
    class MetadataReaderAdapter
      include Core::Ports::MetadataReader

      def initialize(extractor: nil)
        @fallback_extractor = extractor
      end

      def extract_metadata(path)
        extractor = FormatRegistry.metadata_extractor_for(path) || @fallback_extractor
        return {} unless extractor

        if extractor.respond_to?(:from_file)
          extractor.from_file(path)
        elsif extractor.respond_to?(:from_epub)
          extractor.from_epub(path)
        else
          {}
        end
      rescue StandardError
        {}
      end
    end
  end
end
