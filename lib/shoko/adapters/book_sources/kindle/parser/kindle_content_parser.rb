# frozen_string_literal: true

require_relative '../../epub/parser/xhtml_content_parser'

module Shoko
  module Adapters
    module BookSources
      module Kindle
        # Content parser for Kindle/Mobipocket chapter fragments.
        #
        # MOBI/AZW content is a single HTML document and parses directly through
        # the proven EPUB XHTMLContentParser. KF8/AZW3 text, however, is a run of
        # *concatenated* XHTML page-documents using a skeleton+fragment layout:
        # an (often empty) `<body>` skeleton followed by the page's real content
        # fragment, repeated per page. That produces many `<html>` roots (which
        # REXML rejects, collapsing to text-only) and wraps images in
        # `<div class="image-container">` (which the renderer only treats as a
        # real image when the `<img>` is a direct child of `<body>`). So for
        # multi-document content, flatten the skeleton structure into one valid
        # document and promote single-image containers to body level.
        class KindleContentParser
          XHTML_NS = 'http://www.w3.org/1999/xhtml'
          EPUB_NS = 'http://www.idpf.org/2007/ops'

          XML_PI = /<\?xml[^>]*\?>/i
          HEAD_BLOCK = %r{<head\b[^>]*>.*?</head>}mi
          STRUCTURE_TAGS = %r{</?(?:html|body)\b[^>]*>}i
          IMG_ONLY_CONTAINER = %r{<(?:div|p)\b[^>]*>\s*(<img\b[^>]*?/?>)\s*</(?:div|p)>}i

          # @param html [String] HTML/XHTML chapter fragment
          # @param logger [Object, nil] optional logger
          # @param style_resolver [Object, nil] CSS resolver for the chapter
          def initialize(html, logger: nil, style_resolver: nil)
            @html = html.to_s
            @logger = logger
            @style_resolver = style_resolver
          end

          # Parse the chapter HTML into semantic content blocks.
          #
          # @return [Array<Core::Models::ContentBlock>]
          def parse
            Adapters::BookSources::Epub::XHTMLContentParser.new(
              prepared_markup,
              logger: @logger,
              style_resolver: @style_resolver
            ).parse
          end

          private

          def prepared_markup
            return @html unless multiple_documents?

            body = @html.gsub(XML_PI, ' ').gsub(HEAD_BLOCK, ' ').gsub(STRUCTURE_TAGS, ' ')
            %(<html xmlns="#{XHTML_NS}" xmlns:epub="#{EPUB_NS}"><body>#{promote_images(body)}</body></html>)
          end

          def multiple_documents?
            @html.scan(/<html\b/i).length > 1
          end

          # Unwrap containers holding only an image so the image lands at body
          # level. Repeats until stable to handle nested single-image wrappers.
          def promote_images(html)
            previous = nil
            current = html
            until current == previous
              previous = current
              current = current.gsub(IMG_ONLY_CONTAINER, ' \1 ')
            end
            current
          end
        end
      end
    end
  end
end
