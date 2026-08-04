# frozen_string_literal: true

require 'cgi'
require 'rexml/document'
require 'rexml/parsers/pullparser'

require 'shoko/core/models/content_block'
require 'shoko/adapters/support/rexml_safe_parser'
require 'shoko/adapters/support/html_processor'
require_relative 'markup_visibility'
require_relative 'xhtml_segment_builder'
require_relative 'xhtml_block_builder'
require_relative 'xhtml_content_traversal'
require 'shoko/shared/text_sanitizer'
require 'shoko/shared/errors'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Parses XHTML content into semantic content blocks + text segments.
        # Facade: sanitizes and parses the document, then delegates block
        # traversal to XHTMLContentTraversal, block construction to
        # XHTMLBlockBuilder, and inline text to XHTMLSegmentBuilder.
        class XHTMLContentParser
          TAG_SETS = begin
            block_types = %w[p div section article aside header footer figure figcaption main center address].freeze
            heading_types = %w[h1 h2 h3 h4 h5 h6].freeze
            list_types = %w[ul ol].freeze
            list_item = 'li'
            definition_types = %w[dl dt dd].freeze
            blockquote = 'blockquote'
            pre = 'pre'
            hr = 'hr'
            br = 'br'
            img = 'img'
            table = 'table'
            block_level_elements = (
              block_types + heading_types + list_types + definition_types +
                [list_item, blockquote, pre, hr, table]
            ).freeze

            {
              inline_newline: "\n",
              block_types: block_types,
              heading_types: heading_types,
              list_types: list_types,
              list_item: list_item,
              definition_types: definition_types,
              blockquote: blockquote,
              pre: pre,
              hr: hr,
              br: br,
              img: img,
              table: table,
              block_level_elements: block_level_elements,
            }.freeze
          end

          WHITESPACE_PATTERN = /\s+/
          XML_ENTITY_NAMES = %w[amp lt gt apos quot].freeze

          def initialize(html, logger: nil, style_resolver: nil)
            @html = html.to_s
            @logger = logger
            @style_resolver = usable_resolver(style_resolver)
            @segment_builder = XHTMLSegmentBuilder.new(tag_sets: TAG_SETS,
                                                       whitespace_pattern: WHITESPACE_PATTERN,
                                                       style_resolver: @style_resolver)
            @block_builder = XHTMLBlockBuilder.new(segment_builder: @segment_builder,
                                                   tag_sets: TAG_SETS,
                                                   style_resolver: @style_resolver)
          end

          def parse
            return [] if html_blank?

            body = parse_body
            return [] unless body

            build_blocks(body)
          rescue REXML::ParseException => e
            @logger&.error('Failed to parse chapter HTML', error: e.message)
            fallback_blocks
          end

          private

          def html_blank?
            @html.strip.empty?
          end

          def usable_resolver(style_resolver)
            style_resolver if style_resolver&.any_rules?
          end

          def build_blocks(body)
            traversal = XHTMLContentTraversal.new(block_builder: @block_builder,
                                                  tag_sets: TAG_SETS,
                                                  style_resolver: @style_resolver)
            blocks = traversal.build(body)
            ensure_blocks_present(body, blocks)
            blocks
          end

          def parse_body
            document = parse_document(@html)
            return nil unless document

            find_body(document) || document.root
          end

          def parse_document(text)
            safe = Shoko::Shared::TextSanitizer.sanitize_xml_source(text.to_s,
                                                                    preserve_newlines: true,
                                                                    preserve_tabs: true)
            sanitized = sanitize_for_xml(safe)
            # Preserve whitespace-only text nodes so inline element boundaries
            # don't accidentally collapse words (e.g., <em>foo</em>\n<em>bar</em>).
            # We normalize whitespace later in `normalize_text`.
            Shoko::Adapters::Support::REXMLSafeParser.parse(sanitized)
          end

          def sanitize_for_xml(text)
            sanitized = text.gsub(/&([A-Za-z][A-Za-z0-9]+);/) do
              sanitize_entity(Regexp.last_match(0), Regexp.last_match(1))
            end

            # Some EPUBs include raw ampersands in code/text (for example: a&0x80).
            # REXML rejects those as invalid XML, so escape any bare ampersands that
            # are not part of a valid entity reference.
            sanitized = sanitized.gsub(/&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9]+;)/, '&amp;')

            # Some books embed source code with raw comparison operators (for example:
            # i<8), which yields malformed XML. Escape "<" unless it starts a tag-ish
            # construct (opening/closing tag, comment, CDATA, doctype, or PI).
            sanitized.gsub(%r{<(?!/?[A-Za-z]|!--|!\[CDATA\[|!\s*DOCTYPE|\?)}i, '&lt;')
          end

          def sanitize_entity(match, name)
            return match if XML_ENTITY_NAMES.include?(name)

            decoded = Shoko::Adapters::Support::HTMLProcessor.decode_entities(match)
            decoded == match ? "&amp;#{name};" : decoded
          end

          def find_body(document)
            root = document&.root
            return nil unless root

            elements = root.elements
            elements['*[local-name()="body"]'] ||
              elements['body'] ||
              elements['BODY']
          end

          def ensure_blocks_present(body, blocks)
            text_content = body.texts.join.strip
            return if text_content.empty? || blocks.any?

            @logger&.error(
              'Formatting produced no blocks',
              source: 'XHTMLContentParser',
              sample: text_content.slice(0, 120)
            )
            raise Shoko::FormattingError.new('chapter', 'normalized block list was empty')
          end

          def fallback_blocks
            text = Shoko::Adapters::Support::HTMLProcessor.html_to_text(@html)
            return [] if text.to_s.strip.empty?

            paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
            paragraphs.map do |paragraph|
              Shoko::Core::Models::ContentBlock.new(
                type: :paragraph,
                segments: [@segment_builder.text_segment(paragraph)],
                metadata: {}
              )
            end
          end
        end
      end
    end
  end
end
