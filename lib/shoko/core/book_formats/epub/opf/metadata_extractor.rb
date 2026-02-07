# frozen_string_literal: true

require_relative '../html_processor'

module Shoko
  module Core::BookFormats::Epub
    # Extracts metadata fields from an OPF document.
    class OPFMetadataExtractor
      def initialize(opf)
        @opf = opf
      end

      def extract
        metadata_element = @opf.elements['//metadata']
        return {} unless metadata_element

        @elements = metadata_element.elements
        @metadata = {}

        extract_title
        extract_language
        extract_authors
        extract_year

        @metadata
      ensure
        @elements = nil
        @metadata = nil
      end

      private

      def extract_title
        raw_title = @elements['*[local-name()="title"]']&.text
        return unless raw_title

        title = HTMLProcessor.clean_html(raw_title.to_s).strip
        @metadata[:title] = title unless title.empty?
      end

      def extract_language
        lang_text = @elements['*[local-name()="language"]']&.text
        return unless lang_text

        @metadata[:language] = lang_text.include?('_') ? lang_text : "#{lang_text}_#{lang_text.upcase}"
      end

      def extract_authors
        authors = []
        @elements.each('*[local-name()="creator"]') do |creator|
          txt = HTMLProcessor.clean_html(creator.text.to_s).strip
          authors << txt unless txt.empty?
        end
        @metadata[:authors] = authors unless authors.empty?
      end

      def extract_year
        date_elem = @elements['*[local-name()="date"]']
        return unless date_elem

        date_text = date_elem.text.to_s
        match = date_text.match(/(\d{4})/)
        @metadata[:year] = match[1] if match
      end
    end
  end
end
