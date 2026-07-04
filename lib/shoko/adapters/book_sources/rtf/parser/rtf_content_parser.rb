# frozen_string_literal: true

require_relative '../../epub/parser/xhtml_content_parser'

module Shoko
  module Adapters
    module BookSources
      module Rtf
        # Content parser for RTF chapter fragments.
        #
        # The RTF importer converts chapter content to HTML, so this parser
        # delegates to XHTMLContentParser — same pattern as KindleContentParser.
        class RtfContentParser
          # @param html [String] HTML chapter fragment (converted from RTF by importer)
          # @param logger [Object, nil] optional logger
          # style_resolver is accepted for content-parser interface parity;
          # this format has no CSS source, so it is unused.
          def initialize(html, logger: nil, style_resolver: nil)
            @style_resolver = style_resolver
            @delegate = Adapters::BookSources::Epub::XHTMLContentParser.new(html, logger: logger)
          end

          # Parse the chapter HTML into semantic content blocks.
          # @return [Array<Core::Models::ContentBlock>]
          def parse
            @delegate.parse
          end
        end
      end
    end
  end
end
