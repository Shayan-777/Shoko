# frozen_string_literal: true

require 'cgi'
require 'rexml/document'
require 'rexml/parsers/pullparser'

require_relative '../../models/content_block'
require_relative 'rexml_safe_parser'
require_relative 'html_processor'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../shared/errors'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Parses XHTML content into semantic content blocks + text segments.
        class XHTMLContentParser
          TAG_SETS = begin
            block_types = %w[p div section article aside header footer figure figcaption main].freeze
            heading_types = %w[h1 h2 h3 h4 h5 h6].freeze
            list_types = %w[ul ol].freeze
            list_item = 'li'
            blockquote = 'blockquote'
            pre = 'pre'
            hr = 'hr'
            br = 'br'
            img = 'img'
            table = 'table'
            block_level_elements = (
              block_types +
              heading_types +
              list_types +
              [
                list_item,
                blockquote,
                pre,
                hr,
                table,
              ]
            ).freeze

            {
              inline_newline: "\n",
              block_types: block_types,
              heading_types: heading_types,
              list_types: list_types,
              list_item: list_item,
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

          def initialize(html, logger: nil)
            @html = html.to_s
            @logger = logger
            @segment_builder = XHTMLSegmentBuilder.new(tag_sets: TAG_SETS, whitespace_pattern: WHITESPACE_PATTERN)
            @block_builder = XHTMLBlockBuilder.new(segment_builder: @segment_builder, tag_sets: TAG_SETS)
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

          def build_blocks(body)
            blocks = XHTMLContentTraversal.new(block_builder: @block_builder, tag_sets: TAG_SETS).build(body)
            ensure_blocks_present(body, blocks)
            blocks
          end

          def parse_body
            document = parse_document(@html)
            return nil unless document

            find_body(document) || document.root
          end

          def parse_document(text)
            safe = Shoko::Shared::TextSanitizer.sanitize_xml_source(text.to_s, preserve_newlines: true,
                                                                               preserve_tabs: true)
            sanitized = sanitize_for_xml(safe)
            # Preserve whitespace-only text nodes so inline element boundaries
            # don't accidentally collapse words (e.g., <em>foo</em>\n<em>bar</em>).
            # We normalize whitespace later in `normalize_text`.
            REXMLSafeParser.parse(sanitized)
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
            sanitized.gsub(/<(?!\/?[A-Za-z]|!--|!\[CDATA\[|!\s*DOCTYPE|\?)/i, '&lt;')
          end

          def sanitize_entity(match, name)
            return match if XML_ENTITY_NAMES.include?(name)

            decoded = Shoko::Core::BookFormats::Epub::HTMLProcessor.decode_entities(match)
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
            text = Shoko::Core::BookFormats::Epub::HTMLProcessor.html_to_text(@html)
            return [] if text.to_s.strip.empty?

            paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
            paragraphs.map do |paragraph|
              Shoko::Core::Models::ContentBlock.new(
                type: :paragraph,
                segments: [@segment_builder.text_segment(paragraph)],
                metadata: {}
              )
            end
          rescue StandardError
            []
          end
        end

        # Traverses elements and emits block structures.
        class XHTMLContentTraversal
          # Traversal state for list nesting and blockquote context.
          Context = Struct.new(:list_stack, :in_blockquote, keyword_init: true)
          private_constant :Context

          # Tracks ordered list numbering as the traversal enters list items.
          ListContext = Struct.new(:ordered, :index, keyword_init: true) do
            def marker
              ordered ? "#{index}." : '•'
            end

            def advance
              self.index += 1 if ordered
            end
          end
          private_constant :ListContext

          def initialize(block_builder:, tag_sets:)
            @block_builder = block_builder
            @tag_sets = tag_sets
            @blocks = []
          end

          def build(root)
            context = Context.new(list_stack: [], in_blockquote: false)
            traverse_children(root, context)
            @block_builder.compact_blocks(@blocks)
          end

          private

          attr_reader :block_builder, :tag_sets

          def traverse_children(node, context)
            node.children.each { |child| handle_node(child, context) }
          end

          def handle_node(child, context)
            if child.is_a?(REXML::Element)
              handle_element(child, context)
            elsif child.is_a?(REXML::Text)
              append_text_block(child, context)
            end
          end

          def handle_element(element, context)
            name = element.name.downcase
            return if skip_element?(name)

            return if append_block_result(block_builder.block_for(name, element, context))
            return if handle_list_element(name, element, context)
            return if handle_container_element(name, element, context)

            traverse_children(element, context)
          end

          def append_block_result(result)
            return false unless result

            if result.is_a?(Array)
              result.each { |block| append_block(block) }
            else
              append_block(result)
            end
            true
          end

          def handle_list_element(name, element, context)
            list_types = tag_sets[:list_types]
            if list_types.include?(name)
              traverse_list(element, context, ordered: name == 'ol')
              return true
            end

            return false unless name == tag_sets[:list_item]

            append_block(block_builder.list_item(element, context))
            true
          end

          def handle_container_element(name, element, context)
            block_types = tag_sets[:block_types]
            block_level = tag_sets[:block_level_elements]
            return false unless block_types.include?(name) || block_builder.block_via_style?(element)

            if block_builder.contains_block_children?(element, block_level)
              traverse_children(element, context)
            else
              append_block(block_builder.paragraph(element, context))
            end
            true
          end

          def append_text_block(text_node, context)
            segments = block_builder.segments_from_text(text_node.value)
            append_block(block_builder.paragraph_from_segments(segments, context)) if segments
          end

          def traverse_list(element, context, ordered:)
            list_context = ListContext.new(ordered: ordered, index: ordered ? 1 : nil)
            new_context = Context.new(list_stack: context.list_stack + [list_context],
                                      in_blockquote: context.in_blockquote)
            element.each_element { |child| handle_element(child, new_context) }
          end

          def append_block(block)
            @blocks << block if block
          end

          def skip_element?(name)
            %w[script style].include?(name)
          end
        end

        # Builds content blocks and metadata from parsed elements.
        class XHTMLBlockBuilder
          ContentBlock = Shoko::Core::Models::ContentBlock
          ALIGNMENT_MAP = {
            'left' => :left,
            'right' => :right,
            'center' => :center,
            'middle' => :center,
            'justify' => :justify,
            'start' => :left,
            'end' => :right,
          }.freeze

          def initialize(segment_builder:, tag_sets:)
            @segments = segment_builder
            @tag_sets = tag_sets
          end

          def block_for(name, element, context)
            heading = heading_block(name, element, context)
            return heading if heading

            case name
            when @tag_sets[:blockquote]
              quote_block(element, context)
            when @tag_sets[:img]
              image_block(element, context)
            when @tag_sets[:pre]
              preformatted_block(element, context)
            when @tag_sets[:hr]
              separator_block(context)
            when @tag_sets[:table]
              table_blocks(element, context)
            when @tag_sets[:br]
              break_block
            end
          end

          def list_item(element, context)
            list_stack = context.list_stack
            list_context = list_stack.last
            segments = segments_for(element)
            marker = list_context ? list_context.marker : '•'
            list_context&.advance

            level = list_stack.length
            metadata = metadata_with_quote(context, marker: marker, level: level)
            attach_anchor_metadata(metadata, element)
            ContentBlock.new(type: :list_item, segments: segments, level: level, metadata: metadata)
          end

          def paragraph(element, context)
            segments = segments_for(element)
            return nil if segments.empty?

            metadata = metadata_with_quote(context)
            attach_anchor_metadata(metadata, element)
            alignment = alignment_for(element)
            metadata[:align] = alignment if alignment
            ContentBlock.new(type: :paragraph, segments: segments, metadata: metadata)
          end

          def paragraph_from_segments(segments, context)
            return nil if segments.nil? || segments.empty?

            ContentBlock.new(type: :paragraph, segments: segments, metadata: metadata_with_quote(context))
          end

          def segments_from_text(text)
            segment = @segments.text_segment(text)
            segments = @segments.finalize_segments([segment])
            segments.empty? ? nil : segments
          end

          def compact_blocks(blocks)
            blocks.reject do |block|
              next false if block&.type == :break

              block.nil? || block.segments.empty? || block.text.strip.empty?
            end
          end

          def block_via_style?(element)
            style = element.attributes['style'].to_s
            /display\s*:\s*(block|list-item)/i.match?(style)
          end

          def contains_block_children?(element, block_level_elements)
            element.children.any? do |child|
              next false unless child.is_a?(REXML::Element)

              name = child.name.to_s.downcase
              block_level_elements.include?(name) || block_via_style?(child)
            end
          end

          private

          def heading_block(name, element, context)
            heading_types = @tag_sets[:heading_types]
            return nil unless heading_types.include?(name)

            level = name.delete('h').to_i
            segments = segments_for(element)
            metadata = metadata_with_quote(context, level: level)
            attach_anchor_metadata(metadata, element)
            alignment = alignment_for(element)
            metadata[:align] = alignment if alignment
            ContentBlock.new(type: :heading, segments: segments, level: level, metadata: metadata)
          end

          def quote_block(element, context)
            segments = segments_for(element)
            return nil if segments.empty?

            metadata = metadata_with_quote(context, quoted: true)
            attach_anchor_metadata(metadata, element)
            ContentBlock.new(type: :quote, segments: segments, metadata: metadata)
          end

          def preformatted_block(element, context)
            target = code_child_for(element) || element
            text = target.texts.join
            return nil if text.to_s.empty?

            metadata = metadata_with_quote(context, preserve_whitespace: true)
            attach_anchor_metadata(metadata, element)
            segment = @segments.text_segment(text, code: true, preserve_whitespace: true)
            ContentBlock.new(type: :code, segments: [segment], metadata: metadata)
          end

          def image_block(element, context)
            segments = @segments.finalize_segments([@segments.image_placeholder_segment({})])
            return nil if segments.empty?

            attrs = element.attributes
            metadata = metadata_with_quote(context, image: { src: attrs['src'], alt: attrs['alt'] })
            attach_anchor_metadata(metadata, element)
            ContentBlock.new(type: :image, segments: segments, metadata: metadata)
          end

          def separator_block(context)
            metadata = metadata_with_quote(context)
            ContentBlock.new(
              type: :separator,
              segments: [@segments.text_segment('─' * 40)],
              metadata: metadata
            )
          end

          def table_blocks(element, context)
            table = parse_table(element)
            rows = table[:rows]
            return [] if rows.empty?

            lines = rows.map { |row| row[:cells].map { |cell| cell[:text] }.join(' | ') }
            inline_newline = @tag_sets[:inline_newline]
            metadata = metadata_with_quote(context, preserve_whitespace: true, table: table)
            attach_anchor_metadata(metadata, element)
            block = ContentBlock.new(
              type: :table,
              segments: [@segments.text_segment(lines.join(inline_newline), preserve_whitespace: true)],
              metadata: metadata
            )
            [block]
          end

          def break_block
            ContentBlock.new(
              type: :break,
              segments: [],
              metadata: { spacer: true }
            )
          end

          def segments_for(element)
            @segments.finalize_segments(@segments.collect_segments(element))
          end

          def metadata_with_quote(context, base = {})
            metadata = base.dup
            metadata[:quoted] = true if context.in_blockquote
            metadata
          end

          def code_child_for(element)
            element.elements.find do |child|
              child.is_a?(REXML::Element) && child.name.casecmp('code').zero?
            end
          end

          def parse_table(element)
            table_align = alignment_for(element)
            rows = []
            element.children.each do |child|
              next unless child.is_a?(REXML::Element)

              name = child.name.to_s.downcase
              case name
              when 'thead'
                rows.concat(parse_table_section(child, header: true, default_align: table_align))
              when 'tbody', 'tfoot'
                rows.concat(parse_table_section(child, header: false, default_align: table_align))
              when 'tr'
                rows << parse_table_row(child, header: row_has_header_cells?(child), default_align: table_align)
              end
            end

            if rows.empty?
              element.each_element('tr') do |row|
                rows << parse_table_row(row, header: row_has_header_cells?(row), default_align: table_align)
              end
            end

            header_rows = rows.take_while { |row| row[:header] }.length
            { rows: rows, header_rows: header_rows, align: table_align }
          end

          def parse_table_section(section, header:, default_align:)
            rows = []
            section_align = alignment_for(section) || default_align
            section.each_element('tr') do |row|
              rows << parse_table_row(row, header: header || row_has_header_cells?(row), default_align: section_align)
            end
            rows
          end

          def parse_table_row(row, header:, default_align:)
            row_align = alignment_for(row) || default_align
            cells = row.elements.each_with_object([]) do |cell, acc|
              next unless table_cell?(cell)

              cell_header = header || cell.name.to_s.downcase == 'th'
              acc << table_cell_data(cell, header: cell_header, default_align: row_align)
            end

            row_header = header || cells.any? { |cell| cell[:header] }
            { header: row_header, cells: cells, align: row_align }
          end

          def row_has_header_cells?(row)
            row.elements.any? { |cell| table_cell?(cell) && cell.name.to_s.casecmp('th').zero? }
          end

          def table_cell_data(element, header:, default_align:)
            {
              text: table_cell_text(element),
              header: header,
              align: alignment_for(element) || default_align,
              colspan: positive_int_or_one(element.attributes['colspan']),
              rowspan: positive_int_or_one(element.attributes['rowspan']),
            }
          end

          def table_cell_text(element)
            segments = @segments.finalize_segments(@segments.collect_segments(element))
            segments.map(&:text).join
          end

          def attach_anchor_metadata(metadata, element)
            anchors = anchor_ids_for(element)
            metadata[:anchors] = anchors if anchors
          end

          def anchor_ids_for(element)
            return nil unless element.is_a?(REXML::Element)

            ids = []
            collect_anchor_ids(element, ids)
            ids = ids.map { |value| value.to_s.strip }.reject(&:empty?).uniq
            ids.empty? ? nil : ids
          end

          def collect_anchor_ids(element, ids)
            return unless element.is_a?(REXML::Element)

            anchor = element.attributes['id'] || element.attributes['name']
            ids << anchor if anchor && !anchor.to_s.empty?
            element.each_element { |child| collect_anchor_ids(child, ids) }
          end

          def alignment_for(element)
            return nil unless element.is_a?(REXML::Element)

            style_align = alignment_from_style(element.attributes['style'])
            attr_align = element.attributes['align']
            normalize_alignment(style_align || attr_align)
          end

          def alignment_from_style(style)
            style_text = style.to_s
            return nil if style_text.empty?

            match = /text-align\s*:\s*([^;]+)/i.match(style_text)
            match ? match[1] : nil
          end

          def normalize_alignment(value)
            raw = value.to_s.strip.downcase
            return nil if raw.empty?

            normalized = raw.sub(/;+\z/, '')
            normalized = normalized.sub(/\s*!important\z/, '').strip
            ALIGNMENT_MAP[normalized]
          end

          def positive_int_or_one(value)
            num = value.to_i
            num.positive? ? num : 1
          end

          def table_cell?(element)
            %w[td th].include?(element.name.to_s.downcase)
          end
        end

        # Collects and normalizes inline text segments.
        class XHTMLSegmentBuilder
          TextSegment = Shoko::Core::Models::TextSegment

          STYLE_MAP = {
            'strong' => { bold: true },
            'b' => { bold: true },
            'em' => { italic: true },
            'i' => { italic: true },
            'u' => { underline: true },
            's' => { strikethrough: true },
            'strike' => { strikethrough: true },
            'del' => { strikethrough: true },
            'sup' => { superscript: true },
            'sub' => { subscript: true },
            'code' => { code: true, preserve_whitespace: true },
            'kbd' => { code: true, preserve_whitespace: true },
            'samp' => { code: true, preserve_whitespace: true },
          }.freeze

          SPAN_STYLE_MATCHERS = {
            bold: /font-weight\s*:\s*bold/i,
            italic: /font-style\s*:\s*italic/i,
            underline: /text-decoration\s*:\s*underline/i,
            strikethrough: /text-decoration\s*:\s*(?:line-through|line\s+through)/i,
            superscript: /vertical-align\s*:\s*super/i,
            subscript: /vertical-align\s*:\s*sub/i,
          }.freeze

          PLACEHOLDER_TEXT = '[Image]'

          def initialize(tag_sets:, whitespace_pattern:)
            @br_tag = tag_sets[:br]
            @img_tag = tag_sets[:img]
            @inline_newline = tag_sets[:inline_newline]
            @whitespace_pattern = whitespace_pattern
          end

          def collect_segments(element, inherited_styles = {})
            element.children.flat_map { |child| segments_for(child, inherited_styles) }
          end

          def text_segment(text, styles = {})
            TextSegment.new(
              text: normalize_text(text.to_s, styles),
              styles: styles
            )
          end

          def image_placeholder_segment(inherited_styles)
            placeholder_segment(inherited_styles.merge(dim: true))
          end

          def inline_image_placeholder_segment(element, inherited_styles)
            attrs = element.attributes
            styles = inherited_styles.merge(
              dim: true,
              inline_image: { src: attrs['src'].to_s, alt: attrs['alt'].to_s.strip }
            )
            placeholder_segment(styles)
          end

          def finalize_segments(segments)
            segs = compact_segments(segments)
            return [] if segs.empty?

            segs = collapse_boundary_spaces(segs)
            trim_edge_whitespace(segs)
          end

          private

          def segments_for(child, inherited_styles)
            return [] unless child

            if child.is_a?(REXML::Text)
              segment = text_segment(child.value, inherited_styles)
              segment.text.to_s.empty? ? [] : [segment]
            elsif child.is_a?(REXML::Element)
              segments_for_element(child, inherited_styles)
            else
              []
            end
          end

          def segments_for_element(element, inherited_styles)
            name = element.name.downcase
            return [line_break_segment(inherited_styles)] if name == @br_tag
            return [inline_image_placeholder_segment(element, inherited_styles)] if name == @img_tag

            new_styles = inherited_styles.merge(styles_for(name, element))
            collect_segments(element, new_styles)
          end

          def line_break_segment(inherited_styles)
            text_segment(@inline_newline, inherited_styles.merge(break: true))
          end

          def styles_for(name, element)
            return STYLE_MAP[name] if STYLE_MAP.key?(name)
            return span_styles(element) if name == 'span'
            return link_styles(element) if name == 'a'

            {}
          end

          def link_styles(element)
            { link: element.attributes['href'] }.merge(span_styles(element))
          end

          def span_styles(element)
            style_attr = element.attributes['style']
            return {} if style_attr.to_s.empty?

            SPAN_STYLE_MATCHERS.each_with_object({}) do |(key, matcher), styles|
              styles[key] = true if matcher.match?(style_attr)
            end
          end

          def normalize_text(text, styles)
            decoded = decode_text(text)
            return decoded if preserve_whitespace?(styles)
            return normalize_break(decoded) if styles[:break]

            normalize_whitespace(decoded)
          end

          def decode_text(text)
            decoded = Shoko::Core::BookFormats::Epub::HTMLProcessor.decode_entities(text)
            Shoko::Shared::TextSanitizer.sanitize(decoded, preserve_newlines: true,
                                                           preserve_tabs: true)
          end

          def preserve_whitespace?(styles)
            styles[:code] || styles[:preserve_whitespace]
          end

          def normalize_break(text)
            text == @inline_newline ? @inline_newline : text
          end

          def normalize_whitespace(text)
            text.delete("\r").tr("\n", ' ').gsub(@whitespace_pattern, ' ')
          end

          def placeholder_segment(styles)
            text_segment(" #{PLACEHOLDER_TEXT} ", styles)
          end

          def compact_segments(segments)
            Array(segments).compact.reject { |segment| segment_text(segment).empty? }
          end

          def collapse_boundary_spaces(segments)
            out = [segments.first]
            segments.drop(1).each do |segment|
              previous = out.last
              adjusted = adjust_leading_space(previous, segment)
              next unless adjusted

              out << adjusted unless segment_text(adjusted).empty?
            end
            out
          end

          def adjust_leading_space(previous, segment)
            prev_text = segment_text(previous)
            cur_text = segment_text(segment)
            return segment unless prev_text.end_with?(' ') && cur_text.start_with?(' ')

            trimmed = cur_text.sub(/\A +/, '')
            return nil if trimmed.empty?

            TextSegment.new(text: trimmed, styles: segment.styles)
          end

          def trim_edge_whitespace(segments)
            segs = segments.dup
            return [] if segs.empty?

            segs[0] = trim_segment_start(segs[0])
            segs[-1] = trim_segment_end(segs[-1])
            segs.reject { |segment| segment_text(segment).empty? }
          end

          def trim_segment_start(segment)
            text = segment_text(segment).sub(/\A\s+/, '')
            TextSegment.new(text: text, styles: segment.styles)
          end

          def trim_segment_end(segment)
            text = segment_text(segment).sub(/\s+\z/, '')
            TextSegment.new(text: text, styles: segment.styles)
          end

          def segment_text(segment)
            segment.text.to_s
          end
        end
      end
    end
  end
end
