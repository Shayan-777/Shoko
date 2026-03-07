# frozen_string_literal: true

require_relative 'archive/zip_reader'
require_relative '../../core/ports/outbound/metadata_reader'
require_relative '../../core/book_formats/format_registry'

module Shoko
  module Adapters
    module BookSources
      # Adapter implementing the MetadataReader port.
      # Uses FormatRegistry to dispatch to the correct metadata extractor.
      class MetadataReaderAdapter
        include Core::Ports::Outbound::MetadataReader

        def initialize(file_probe:, path_ops:, file_reader:, text_reader:, zip_open:, zip_entry_reader:)
          @file_probe = file_probe
          @path_ops = path_ops
          @file_reader = file_reader
          @text_reader = text_reader
          @zip_open = zip_open
          @zip_entry_reader = zip_entry_reader
        end

        def extract_metadata(path)
          extractor = Core::BookFormats::FormatRegistry.metadata_extractor_for(path)
          raise Shoko::MalformedMetadataInputError, "no metadata extractor for #{path}" unless extractor

          metadata = if epub_path?(path)
                       extractor.from_epub(path, zip_open: @zip_open)
                     else
                       extractor.from_file(
                         path,
                         file_probe: @file_probe,
                         path_ops: @path_ops,
                         file_reader: @file_reader,
                         text_reader: @text_reader,
                         zip_open: @zip_open,
                         zip_entry_reader: @zip_entry_reader
                       )
                     end
          unless metadata.is_a?(Hash)
            raise Shoko::MalformedMetadataInputError, "metadata extractor returned #{metadata.class} for #{path}"
          end

          metadata
        rescue Shoko::Error, ArgumentError, TypeError => e
          raise if e.is_a?(Shoko::MalformedMetadataInputError) || e.is_a?(Shoko::MalformedBookInputError)

          raise Shoko::MalformedMetadataInputError, "metadata extraction failed for #{path}: #{e.message}"
        end

        private

        def epub_path?(path)
          path.to_s.downcase.end_with?('.epub')
        end
      end
    end
  end
end
