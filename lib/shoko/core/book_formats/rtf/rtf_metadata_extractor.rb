# frozen_string_literal: true

require_relative 'rtf_parser'
require_relative 'metadata_parser'
require_relative '../../ports/outbound/path_ops'

module Shoko
  module Core
    module BookFormats
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
              return {} unless file_probe&.file?(path)
              return {} unless file_reader
              unless path_ops.is_a?(Shoko::Core::Ports::Outbound::PathOps)
                raise ArgumentError, 'path_ops must implement Core::Ports::Outbound::PathOps'
              end

              raw = file_reader.call(path).to_s.force_encoding('BINARY')
              content = raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

              doc = RtfParser.new(content).parse
              canonical = MetadataParser.parse(
                doc: doc,
                fallback_title: fallback_title(path, path_ops: path_ops)
              )
              authors = Array(canonical[:authors]).map(&:to_s).reject(&:empty?)

              {
                title: canonical[:title],
                authors: authors,
                author_str: authors.empty? ? nil : authors.join('; '),
                year: canonical[:year],
                language: canonical[:language]
              }.compact
            rescue ArgumentError
              raise
            rescue StandardError
              {}
            end

            private

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
