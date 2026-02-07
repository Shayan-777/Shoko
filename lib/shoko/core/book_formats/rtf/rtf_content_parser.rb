# frozen_string_literal: true

require_relative '../epub/xhtml_content_parser'

module Shoko
  module Core::BookFormats::Rtf
    # Content parser for RTF chapter fragments.
    #
    # The RTF importer converts chapter content to HTML, so this parser
    # delegates to XHTMLContentParser — same pattern as KindleContentParser.
    class RtfContentParser
      # @param html [String] HTML chapter fragment (converted from RTF by importer)
      # @param logger [Object, nil] optional logger
      def initialize(html, logger: nil)
        @delegate = Core::BookFormats::Epub::XHTMLContentParser.new(html, logger: logger)
      end

      # Parse the chapter HTML into semantic content blocks.
      # @return [Array<Core::Models::ContentBlock>]
      def parse
        @delegate.parse
      end
    end
  end
end
