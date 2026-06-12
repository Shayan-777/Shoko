# frozen_string_literal: true

require_relative 'rtf_parser'
require_relative 'metadata_parser'
require_relative '../../../../application/ports/outbound/path_ops'

module Shoko
  module Adapters
    module BookSources
      module Rtf
        # Lightweight metadata extractor for RTF files.
        # Implements the self.from_file(path) interface used by FormatRegistry.
        module RtfMetadataExtractor
          class << self
            # @param path [String] path to RTF file
            # @param file_probe [#file?, nil] file probe dependency
            # @param file_reader [#call, nil] binary file reader
            # @param path_ops [#basename, nil] path utility dependency
            # @return [Hash] metadata hash with :title, :authors, :author_str, :year, :language
            def from_file(path, file_probe: nil, file_reader: nil, path_ops: nil, **_)
              validate_dependencies!(path, file_probe, file_reader, path_ops)
              canonical = parse_canonical_metadata(path, file_reader: file_reader, path_ops: path_ops)
              canonical_metadata_hash(canonical)
            rescue Shoko::Error, ArgumentError, TypeError => e
              raise if e.is_a?(Shoko::MalformedMetadataInputError)

              raise Shoko::MalformedMetadataInputError, "RTF metadata extraction failed for #{path}: #{e.message}"
            end

            private

            def validate_dependencies!(path, file_probe, file_reader, path_ops)
              raise ArgumentError, "path is not a file: #{path}" unless file_probe&.file?(path)
              raise ArgumentError, 'file_reader is required' unless file_reader
              return if path_ops.is_a?(Shoko::Application::Ports::Outbound::PathOps)

              raise ArgumentError, 'path_ops must implement Application::Ports::Outbound::PathOps'
            end

            def parse_canonical_metadata(path, file_reader:, path_ops:)
              doc = RtfParser.new(read_rtf_content(path, file_reader)).parse
              MetadataParser.parse(doc: doc, fallback_title: fallback_title(path, path_ops: path_ops))
            end

            def read_rtf_content(path, file_reader)
              raw = file_reader.call(path).to_s.force_encoding('BINARY')
              validate_rtf_signature!(raw, path)
              raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
            end

            def validate_rtf_signature!(raw, path)
              return if raw.match?(/\A\s*\{\\rtf/i)

              raise Shoko::MalformedMetadataInputError, "RTF header signature missing for #{path}"
            end

            def canonical_metadata_hash(canonical)
              authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)
              {
                title: canonical[:title],
                authors: authors,
                author_str: authors.empty? ? nil : authors.join('; '),
                year: canonical[:year],
                language: canonical[:language],
              }.compact
            end

            def fallback_title(path, path_ops: nil)
              basename = basename_for(path, path_ops: path_ops).sub(/\.[^.]+\z/, '')
              # Try to extract title from "Title (Author).rtf" pattern
              if (m = basename.match(/\A(.+?)\s*\(.*\)\s*\z/))
                m[1].strip
              else
                basename.tr('_', ' ').strip
              end
            end

            def basename_for(path, path_ops: nil)
              path_ops.basename(path).to_s
            end
          end
        end
      end
    end
  end
end
