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

        def initialize(file_probe: nil, path_ops: nil,
                       file_reader: nil, text_reader: nil, zip_open: nil, zip_entry_reader: nil,
                       runtime_config: nil,
                       archive_reader: Shoko::Adapters::BookSources::Archive::ZipReader)
          @file_probe = file_probe
          @path_ops = path_ops
          @file_reader = file_reader || ->(path) { File.binread(path) }
          @text_reader = text_reader || ->(path) { File.read(path, encoding: 'UTF-8') }
          @runtime_config = runtime_config
          @archive_reader = archive_reader
          @zip_open = zip_open || lambda { |path, &block|
            @archive_reader.open(path, runtime_config: @runtime_config, &block)
          }
          @zip_entry_reader = zip_entry_reader || lambda { |path, suffix|
            @archive_reader.open(path, runtime_config: @runtime_config) do |zip|
              entry = zip.entries.find { |e| e.name.downcase.end_with?(suffix.to_s.downcase) }
              entry ? zip.read(entry.name) : nil
            end
          }
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
