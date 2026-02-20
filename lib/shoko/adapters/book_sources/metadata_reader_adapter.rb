# frozen_string_literal: true

require_relative 'archive/zip_reader'
require_relative '../../core/ports/metadata_reader'
require_relative '../../core/book_formats/format_registry'

module Shoko
  module Adapters::BookSources
    # Adapter implementing the MetadataReader port.
    # Uses FormatRegistry to dispatch to the correct metadata extractor
      # based on file extension, with a fallback extractor for legacy usage.
      class MetadataReaderAdapter
      include Core::Ports::MetadataReader

      def initialize(extractor: nil, file_probe: nil, path_ops: nil,
                     file_reader: nil, text_reader: nil, zip_open: nil, zip_entry_reader: nil,
                     runtime_config: nil,
                     archive_reader: Shoko::Adapters::BookSources::Archive::ZipReader)
        @fallback_extractor = extractor
        @file_probe = file_probe
        @path_ops = path_ops
        @file_reader = file_reader || ->(path) { File.binread(path) }
        @text_reader = text_reader || ->(path) { File.read(path, encoding: 'UTF-8') }
        @runtime_config = runtime_config
        @archive_reader = archive_reader
        @zip_open = zip_open || ->(path, &block) { @archive_reader.open(path, runtime_config: @runtime_config, &block) }
        @zip_entry_reader = zip_entry_reader || lambda { |path, suffix|
          @archive_reader.open(path, runtime_config: @runtime_config) do |zip|
            entry = zip.entries.find { |e| e.name.downcase.end_with?(suffix.to_s.downcase) }
            entry ? zip.read(entry.name) : nil
          end
        }
      end

      def extract_metadata(path)
        extractor = FormatRegistry.metadata_extractor_for(path) || @fallback_extractor
        return {} unless extractor

        if extractor.respond_to?(:from_file)
          extractor.from_file(
            path,
            file_probe: @file_probe,
            path_ops: @path_ops,
            file_reader: @file_reader,
            text_reader: @text_reader,
            zip_open: @zip_open,
            zip_entry_reader: @zip_entry_reader
          )
        elsif extractor.respond_to?(:from_epub)
          extractor.from_epub(path, zip_open: @zip_open)
        else
          {}
        end
      rescue StandardError
        {}
      end
    end
  end
end
