# frozen_string_literal: true

require 'cgi'

require_relative '../html_processor'
require_relative 'navigation_document_index'

module Shoko
  module Core::BookFormats::Epub
    # Resolves placeholder navigation labels using heading fallbacks.
    class OPFNavigationLabelResolver
      PLACEHOLDER_PATTERN = /\A[cC][0-9A-Za-z]{2,}\z/

      attr_reader :source_path

      def initialize(entry_reader:, source_path:)
        @entry_reader = entry_reader
        @source_path = source_path
        @text_cleaner = HTMLProcessor
        @document_index = OPFNavigationDocumentIndex.new(entry_reader: entry_reader, cleaner: self)
      end

      def clean_label(text)
        @text_cleaner.clean_html(text.to_s).strip
      end

      def resolve(href:, title:)
        stripped = title.to_s.strip
        return stripped unless href && (stripped.empty? || stripped.match?(PLACEHOLDER_PATTERN))

        clean_label(fallback_label_for(href, stripped))
      rescue StandardError
        stripped
      end

      def document_and_anchor(href:)
        decoded = CGI.unescape(href.to_s)
        return [nil, nil] if decoded.empty?

        base, anchor = decoded.split('#', 2)
        return [nil, anchor] if base.to_s.empty? || @source_path.to_s.empty?

        [expanded_document_path(base), anchor]
      end

      def target_for(href:)
        document_path, = document_and_anchor(href: href)
        return [nil, nil] unless document_path

        [document_path, @entry_reader.opf_relative_path(document_path)]
      end

      private

      def fallback_label_for(href, stripped)
        candidate = heading_label_for(href)
        candidate.to_s.strip.empty? ? stripped : candidate
      end

      def expanded_document_path(base)
        base_dir = File.dirname(@source_path)
        @entry_reader.expand_path(base_dir, base)
      end

      def heading_label_for(href)
        document_path, anchor = document_and_anchor(href: href)
        return nil unless document_path

        return anchor_label(document_path, anchor) if anchor

        @document_index.next_heading(document_path)
      end

      def anchor_label(document_path, anchor)
        candidate = @document_index.anchor_label(document_path, anchor)
        @document_index.remove_heading(document_path, candidate) if candidate
        return candidate unless candidate.to_s.strip.empty?

        @document_index.next_heading(document_path)
      end
    end
  end
end
