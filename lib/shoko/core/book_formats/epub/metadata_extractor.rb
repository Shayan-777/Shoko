# frozen_string_literal: true

require 'rexml/document'

require_relative 'opf_processor'
require_relative 'rexml_safe_parser'

module Shoko
  module Core::BookFormats::Epub
    # Lightweight extractor for common EPUB metadata (authors, year)
    # Reads OPF metadata from an opened EPUB archive.
    class MetadataExtractor
      def self.from_epub(path, zip_open: nil)
        return {} unless zip_open

        zip_open.call(path) do |zip|
          opf_path = find_opf_path(zip)
          return {} unless opf_path

          processor = OPFProcessor.new(opf_path, zip: zip)
          meta = processor.extract_metadata
          normalize(meta)
        end
      rescue StandardError
        {}
      end

      def self.find_opf_path(zip)
        container_xml = zip.read('META-INF/container.xml')
        container = REXMLSafeParser.parse(container_xml)
        rootfile = container.elements['//rootfile']
        return nil unless rootfile

        opf_path = rootfile.attributes['full-path']
        zip.find_entry(opf_path) ? opf_path : nil
      rescue StandardError
        nil
      end

      def self.normalize(meta)
        return {} unless meta.is_a?(Hash)

        authors = Array(meta[:authors]).compact.map(&:to_s).reject(&:empty?)
        {
          authors: authors,
          author_str: authors.join('; '),
          year: (meta[:year] || '').to_s[0, 4],
          title: meta[:title],
          language: meta[:language],
        }
      end
      private_class_method :find_opf_path, :normalize
    end
  end
end
