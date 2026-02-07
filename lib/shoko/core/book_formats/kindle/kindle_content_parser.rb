# frozen_string_literal: true

require_relative '../epub/xhtml_content_parser'

module Shoko
  module Core::BookFormats::Kindle
    # Content parser for Kindle/Mobipocket chapter fragments.
    #
    # Delegates to the proven XHTMLContentParser since MOBI/AZW content
    # is HTML and AZW3/KF8 content is XHTML — both are valid inputs
    # for the existing EPUB parser.
    class KindleContentParser
      # @param html [String] HTML/XHTML chapter fragment
      # @param logger [Object, nil] optional logger
      def initialize(html, logger: nil)
        @delegate = Core::BookFormats::Epub::XHTMLContentParser.new(html, logger: logger)
      end

      # Parse the chapter HTML into semantic content blocks.
      #
      # @return [Array<Core::Models::ContentBlock>]
      def parse
        @delegate.parse
      end
    end
  end
end
