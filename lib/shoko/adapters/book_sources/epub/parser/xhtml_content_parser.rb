# frozen_string_literal: true

require 'cgi'
require 'rexml/document'
require 'rexml/parsers/pullparser'

require 'shoko/core/models/content_block'
require_relative 'rexml_safe_parser'
require_relative 'html_processor'
require_relative 'list_marker'
require 'shoko/shared/text_sanitizer'
require 'shoko/shared/errors'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Parses XHTML content into semantic content blocks + text segments.
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
            style_resolver if style_resolver.respond_to?(:any_rules?) && style_resolver.any_rules?
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
            sanitized.gsub(%r{<(?!/?[A-Za-z]|!--|!\[CDATA\[|!\s*DOCTYPE|\?)}i, '&lt;')
          end

          def sanitize_entity(match, name)
            return match if XML_ENTITY_NAMES.include?(name)

            decoded = Shoko::Adapters::BookSources::Epub::HTMLProcessor.decode_entities(match)
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
            text = Shoko::Adapters::BookSources::Epub::HTMLProcessor.html_to_text(@html)
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

        # Traverses elements and emits block structures.
        class XHTMLContentTraversal
          # Traversal state: list nesting, blockquote membership, inherited
          # alignment, semantic role scope (subtitle/verse/caption), and the
          # boxed-container group blocks belong to.
          Context = Struct.new(:list_stack, :in_blockquote, :align, :role, :box_group)
          private_constant :Context

          VERSE_TYPE_PATTERN = /(?:\bverse\b|\bpoem\b|z3998:verse|z3998:poem)/i

          def initialize(block_builder:, tag_sets:, style_resolver: nil)
            @block_builder = block_builder
            @tag_sets = tag_sets
            @style_resolver = style_resolver
            @blocks = []
            @pending_anchors = []
            @pending_spacing_before = nil
            @box_counter = 0
          end

          def build(root)
            context = Context.new(list_stack: [], in_blockquote: false, align: nil, role: nil, box_group: nil)
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
            return if hidden_element?(element)

            context = semantic_context(name, element, context)
            return if appended_block_result?(block_builder.block_for(name, element, context))
            return if handled_quote_element?(name, element, context)
            return if handled_list_element?(name, element, context)
            return if handled_definition_element?(name, element, context)
            return if handled_container_element?(name, element, context)

            with_container_spacing(element) { traverse_children(element, context) }
          end

          # Semantic scopes an element opens for its descendants: hgroup title
          # paragraphs become subtitles, epub:type verse/poem containers mark
          # verse blocks, and figcaption paragraphs become captions.
          def semantic_context(name, element, context)
            role = semantic_role(name, element)
            role ? context_with(context, role: role) : context
          end

          def semantic_role(name, element)
            return :subtitle if name == 'hgroup'
            return :caption if name == 'figcaption'

            epub_type = element.attributes['epub:type'].to_s
            return nil if epub_type.empty?
            return :verse if VERSE_TYPE_PATTERN.match?(epub_type)
            return :epigraph if epub_type.include?('epigraph')

            nil
          end

          def context_with(context, **overrides)
            Context.new(
              list_stack: overrides.fetch(:list_stack, context.list_stack),
              in_blockquote: overrides.fetch(:in_blockquote, context.in_blockquote),
              align: overrides.fetch(:align, context.align),
              role: overrides.fetch(:role, context.role),
              box_group: overrides.fetch(:box_group, context.box_group)
            )
          end

          def appended_block_result?(result)
            return false unless result

            if result.is_a?(Array)
              result.each { |block| append_block(block) }
            else
              append_block(result)
            end
            true
          end

          def handled_quote_element?(name, element, context)
            return false unless name == tag_sets[:blockquote]

            if block_builder.contains_block_children?(element, tag_sets[:block_level_elements])
              with_container_spacing(element) { traverse_children(element, quoted_context(context)) }
            else
              append_block(block_builder.quote_block(element, context))
            end
            true
          end

          def quoted_context(context)
            context_with(context, in_blockquote: true)
          end

          def handled_list_element?(name, element, context)
            if tag_sets[:list_types].include?(name)
              traverse_list(element, context, ordered: name == 'ol')
              return true
            end

            return false unless name == tag_sets[:list_item]

            item, block_children = block_builder.list_item_with_children(element, context)
            append_block(item)
            block_children.each { |child| handle_element(child, context) }
            true
          end

          def handled_definition_element?(name, element, context)
            return false unless tag_sets[:definition_types].include?(name)

            case name
            when 'dl' then traverse_children(element, context)
            when 'dt' then append_block(block_builder.term_block(element, context))
            when 'dd' then handle_definition_description(element, context)
            end
            true
          end

          def handle_definition_description(element, context)
            if block_builder.contains_block_children?(element, tag_sets[:block_level_elements])
              traverse_children(element, context)
            else
              append_block(block_builder.definition_block(element, context))
            end
          end

          def handled_container_element?(name, element, context)
            block_types = tag_sets[:block_types]
            block_level = tag_sets[:block_level_elements]
            return false unless block_types.include?(name) || block_builder.block_via_style?(element)

            child_context = container_child_context(name, element, context)
            if block_builder.contains_block_children?(element, block_level)
              with_container_spacing(element) { traverse_children(element, child_context) }
            else
              append_block(block_builder.paragraph(element, child_context))
            end
            true
          end

          # A container's own margins land on its first and last emitted
          # blocks, collapsing with the blocks' own margins the way CSS
          # collapses adjacent vertical margins (the larger one wins).
          def with_container_spacing(element)
            spacing = container_spacing(element)
            before = spacing[:spacing_before]
            @pending_spacing_before = [@pending_spacing_before.to_i, before].max if before
            first_index = @blocks.length
            yield
            apply_container_spacing_after(first_index, spacing[:spacing_after])
          end

          def container_spacing(element)
            return {} unless @style_resolver

            metadata = @style_resolver.block_metadata(element)
            { spacing_before: metadata[:spacing_before], spacing_after: metadata[:spacing_after] }
          end

          def apply_container_spacing_after(first_index, spacing_after)
            return unless spacing_after

            last = @blocks.last
            return unless last && @blocks.length > first_index

            current = last.metadata[:spacing_after].to_i
            last.metadata[:spacing_after] = [current, spacing_after].max
          end

          def container_child_context(name, element, context)
            child_context = name == 'center' ? context_with(context, align: :center) : context
            return child_context unless boxed_container?(element)

            @box_counter += 1
            context_with(child_context, box_group: @box_counter)
          end

          def boxed_container?(element)
            @style_resolver&.block_metadata(element)&.dig(:boxed) ? true : false
          end

          def append_text_block(text_node, context)
            segments = block_builder.segments_from_text(text_node.value)
            append_block(block_builder.paragraph_from_segments(segments, context)) if segments
          end

          def traverse_list(element, context, ordered:)
            list_context = ListMarker.context_for(element,
                                                  ordered: ordered,
                                                  depth: context.list_stack.length,
                                                  css_style: @style_resolver&.list_style(element))
            new_context = context_with(context, list_stack: context.list_stack + [list_context])
            element.each_element { |child| handle_element(child, new_context) }
          end

          def append_block(block)
            return unless block

            attach_pending_anchors(block)
            attach_pending_spacing(block)
            @blocks << block
          end

          def attach_pending_spacing(block)
            return unless @pending_spacing_before

            current = block.metadata[:spacing_before].to_i
            block.metadata[:spacing_before] = [current, @pending_spacing_before].max
            @pending_spacing_before = nil
          end

          def skip_element?(name)
            %w[script style].include?(name)
          end

          # Elements hidden via CSS are pruned, but any anchor ids inside them
          # must survive — TOC entries and footnote links target them. They are
          # carried onto the next visible block.
          def hidden_element?(element)
            return false unless @style_resolver&.display_none?(element)

            @pending_anchors.concat(block_builder.anchor_ids_for(element) || [])
            true
          end

          def attach_pending_anchors(block)
            return if @pending_anchors.empty?

            anchors = Array(block.metadata[:anchors]) + @pending_anchors
            block.metadata[:anchors] = anchors.uniq
            @pending_anchors = []
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

          def initialize(segment_builder:, tag_sets:, style_resolver: nil)
            @segments = segment_builder
            @tag_sets = tag_sets
            @style_resolver = style_resolver
          end

          def block_for(name, element, context)
            heading_block(name, element, context) || special_block(name, element, context)
          end

          def anchor_ids_for(element)
            return nil unless element.is_a?(REXML::Element)

            ids = []
            collect_anchor_ids(element, ids)
            ids = ids.map { |value| value.to_s.strip }.reject(&:empty?).uniq
            ids.empty? ? nil : ids
          end

          # Splits a list item into its own inline content plus any block-level
          # children (nested lists, paragraphs) the traversal must handle after
          # the item itself, so nested structures keep their markers and depth.
          def list_item_with_children(element, context)
            inline_children, block_children = partition_list_item_children(element)
            segments = list_item_segments(inline_children, block_children)
            [build_list_item(segments, element, context), block_children]
          end

          def paragraph(element, context)
            segments = segments_for(element, block_seed_styles(element))
            return nil if segments.empty?

            metadata = block_metadata(element, context)
            alignment = alignment_for(element) || metadata[:align] || context.align
            metadata[:align] = alignment if alignment
            ContentBlock.new(type: paragraph_type(context), segments: segments, metadata: metadata)
          end

          def paragraph_from_segments(segments, context)
            return nil if segments.nil? || segments.empty?

            ContentBlock.new(type: paragraph_type(context), segments: segments, metadata: metadata_with_quote(context))
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
            return true if /display\s*:\s*(block|list-item)/i.match?(style)

            @style_resolver ? @style_resolver.block_display?(element) : false
          end

          def contains_block_children?(element, block_level_elements)
            element.children.any? do |child|
              next false unless child.is_a?(REXML::Element)

              name = child.name.to_s.downcase
              block_level_elements.include?(name) || block_via_style?(child)
            end
          end

          def quote_block(element, context)
            segments = segments_for(element, block_seed_styles(element))
            return nil if segments.empty?

            metadata = block_metadata(element, context, quoted: true)
            alignment = alignment_for(element) || metadata[:align] || context.align
            metadata[:align] = alignment if alignment
            ContentBlock.new(type: :quote, segments: segments, metadata: metadata)
          end

          def term_block(element, context)
            segments = segments_for(element, block_seed_styles(element).merge(bold: true))
            return nil if segments.empty?

            metadata = block_metadata(element, context, role: :term)
            ContentBlock.new(type: :paragraph, segments: segments, metadata: metadata)
          end

          def definition_block(element, context)
            segments = segments_for(element, block_seed_styles(element))
            return nil if segments.empty?

            metadata = block_metadata(element, context, role: :definition)
            metadata[:indent_left] = 4 unless metadata.key?(:indent_left)
            ContentBlock.new(type: :paragraph, segments: segments, metadata: metadata)
          end

          private

          def paragraph_type(context)
            context.in_blockquote ? :quote : :paragraph
          end

          # Inline styles a block-level element passes down to its segments:
          # the CSS computed style (inherited included) overridden by the
          # element's own style="" attribute.
          def block_seed_styles(element)
            css = @style_resolver ? @style_resolver.inline_styles(element) : {}
            attr_styles = @segments.style_attributes(element)
            return attr_styles if css.empty?

            css.merge(attr_styles)
          end

          # Base block metadata: quote context, CSS block typography
          # (alignment, indents, spacing), anchors, and any extra pairs.
          def block_metadata(element, context, extra = {})
            metadata = metadata_with_quote(context, extra)
            if @style_resolver
              css = @style_resolver.block_metadata(element)
              metadata = css.merge(metadata) unless css.empty?
            end
            attach_anchor_metadata(metadata, element)
            metadata
          end

          def partition_list_item_children(element)
            block_level = @tag_sets[:block_level_elements]
            element.children.partition do |child|
              !block_level_child?(child, block_level)
            end
          end

          def block_level_child?(child, block_level)
            return false unless child.is_a?(REXML::Element)

            block_level.include?(child.name.to_s.downcase) || block_via_style?(child)
          end

          def list_item_segments(inline_children, block_children)
            segments = @segments.finalize_segments(@segments.segments_from_children(inline_children))
            return segments unless segments.empty?

            promoted = promotable_list_item_lead(block_children)
            return segments unless promoted

            block_children.delete(promoted)
            segments_for(promoted, @segments.style_attributes(promoted))
          end

          # A list item whose only content is a single leading paragraph-like
          # child renders that child as the item text itself.
          def promotable_list_item_lead(block_children)
            lead = block_children.first
            return nil unless lead.is_a?(REXML::Element)
            return nil unless @tag_sets[:block_types].include?(lead.name.to_s.downcase)
            return nil if contains_block_children?(lead, @tag_sets[:block_level_elements])

            lead
          end

          def build_list_item(segments, element, context)
            list_context = context.list_stack.last
            ListMarker.apply_item_value(list_context, element)
            marker = list_context ? list_context.marker : '•'
            list_context&.advance

            level = [context.list_stack.length, 1].max
            metadata = block_metadata(element, context, marker: marker, level: level)
            ContentBlock.new(type: :list_item, segments: segments, level: level, metadata: metadata)
          end

          def heading_block(name, element, context)
            heading_types = @tag_sets[:heading_types]
            return nil unless heading_types.include?(name)

            level = name.delete('h').to_i
            segments = segments_for(element, block_seed_styles(element))
            metadata = block_metadata(element, context, level: level)
            metadata.delete(:role) if metadata[:role] == :subtitle
            alignment = alignment_for(element) || metadata[:align] || context.align
            metadata[:align] = alignment if alignment
            ContentBlock.new(type: :heading, segments: segments, level: level, metadata: metadata)
          end

          def preformatted_block(element, context)
            target = code_child_for(element) || element
            seed = { code: true, preserve_whitespace: true }
            segments = @segments.collect_segments(target, seed)
            segments = [@segments.text_segment(target.texts.join, seed)] if segments.empty?
            return nil if segments.all? { |segment| segment.text.to_s.empty? }

            metadata = metadata_with_quote(context, preserve_whitespace: true)
            attach_anchor_metadata(metadata, element)
            ContentBlock.new(type: :code, segments: segments, metadata: metadata)
          end

          def image_block(element, context)
            attrs = element.attributes
            placeholder = @segments.image_placeholder_segment({}, alt: attrs['alt'])
            segments = @segments.finalize_segments([placeholder])
            return nil if segments.empty?

            metadata = block_metadata(element, context, image: { src: attrs['src'], alt: attrs['alt'] })
            ContentBlock.new(type: :image, segments: segments, metadata: metadata)
          end

          def separator_block(context)
            metadata = metadata_with_quote(context)
            ContentBlock.new(type: :separator, segments: [@segments.text_segment('─' * 40)], metadata: metadata)
          end

          def break_block
            ContentBlock.new(type: :break, segments: [], metadata: { spacer: true })
          end

          def segments_for(element, seed_styles = {})
            @segments.finalize_segments(@segments.collect_segments(element, seed_styles))
          end

          def metadata_with_quote(context, base = {})
            metadata = base.dup
            metadata[:quoted] = true if context.in_blockquote
            metadata[:role] = context.role if context.role && !metadata.key?(:role)
            metadata[:box_group] = context.box_group if context.box_group
            metadata
          end

          def special_block(name, element, context)
            case name
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

          def code_child_for(element)
            element.elements.find do |child|
              child.is_a?(REXML::Element) && child.name.casecmp('code').zero?
            end
          end

          # Shared anchor/alignment extraction for block metadata assembly.
          def attach_anchor_metadata(metadata, element)
            anchors = anchor_ids_for(element)
            metadata[:anchors] = anchors if anchors
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

          # Shared table extraction and normalization for XHTML content blocks.
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

          def parse_table(element)
            table_align = alignment_for(element)
            rows = collect_table_rows(element, table_align)
            rows = collect_direct_table_rows(element, table_align) if rows.empty?
            table = { rows: rows, header_rows: header_row_count(rows), align: table_align }
            caption = table_caption_text(element)
            table[:caption] = caption if caption
            table
          end

          def table_caption_text(element)
            caption = element.elements.find do |child|
              child.is_a?(REXML::Element) && child.name.to_s.casecmp('caption').zero?
            end
            return nil unless caption

            text = table_cell_text(caption)
            text.strip.empty? ? nil : text.strip
          end

          def collect_table_rows(element, table_align)
            element.children.each_with_object([]) do |child, rows|
              next unless child.is_a?(REXML::Element)

              append_table_rows(rows, child, table_align)
            end
          end

          def append_table_rows(rows, child, table_align)
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

          def collect_direct_table_rows(element, table_align)
            element.each_element('tr').map do |row|
              parse_table_row(row, header: row_has_header_cells?(row), default_align: table_align)
            end
          end

          def header_row_count(rows)
            rows.take_while { |row| row[:header] }.length
          end

          def parse_table_section(section, header:, default_align:)
            rows = []
            section_align = alignment_for(section) || default_align
            section.each_element('tr') do |row|
              row_header = header || row_has_header_cells?(row)
              rows << parse_table_row(row, header: row_header, default_align: section_align)
            end
            rows
          end

          def parse_table_row(row, header:, default_align:)
            row_align = alignment_for(row) || default_align
            cells = table_cells(row, header, row_align)
            row_header = header || cells.any? { |cell| cell[:header] }
            { header: row_header, cells: cells, align: row_align }
          end

          def table_cells(row, header, row_align)
            row.elements.each_with_object([]) do |cell, acc|
              next unless table_cell?(cell)

              cell_header = header || cell.name.to_s.downcase == 'th'
              acc << table_cell_data(cell, header: cell_header, default_align: row_align)
            end
          end

          def row_has_header_cells?(row)
            row.elements.any? { |cell| table_cell?(cell) && cell.name.to_s.casecmp('th').zero? }
          end

          def table_cell_data(element, header:, default_align:)
            {
              text: table_cell_text(element),
              segments: table_cell_segments(element),
              header: header,
              align: alignment_for(element) || default_align,
              colspan: positive_int_or_one(element.attributes['colspan']),
              rowspan: positive_int_or_one(element.attributes['rowspan']),
            }
          end

          def table_cell_text(element)
            table_cell_segments(element).map(&:text).join
          end

          def table_cell_segments(element)
            @segments.finalize_segments(@segments.collect_segments(element))
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
            'cite' => { italic: true },
            'dfn' => { italic: true },
            'var' => { italic: true },
            'mark' => { highlight: true },
            'ins' => { underline: true },
            'tt' => { code: true },
            'small' => { small: true },
            'big' => { large: true },
          }.freeze

          SPAN_STYLE_MATCHERS = {
            bold: /font-weight\s*:\s*(?:bold|[6-9]00)/i,
            italic: /font-style\s*:\s*(?:italic|oblique)/i,
            underline: /text-decoration(?:-line)?\s*:\s*[^;]*underline/i,
            strikethrough: /text-decoration(?:-line)?\s*:\s*[^;]*(?:line-through|line\s+through)/i,
            superscript: /vertical-align\s*:\s*super/i,
            subscript: /vertical-align\s*:\s*sub/i,
            small_caps: /font-variant(?:-caps)?\s*:\s*[^;]*small-caps/i,
          }.freeze

          COLOR_STYLE_PATTERN = /(?<!background-)\bcolor\s*:\s*([^;]+)/i
          BACKGROUND_STYLE_PATTERN = /background(?:-color)?\s*:\s*([^;]+)/i
          NON_COLOR_VALUES = %w[inherit initial unset transparent currentcolor none].freeze
          SKIPPED_INLINE_ELEMENTS = %w[rt rp].freeze
          MAX_ALT_LENGTH = 60

          PLACEHOLDER_TEXT = '[Image]'

          def initialize(tag_sets:, whitespace_pattern:, style_resolver: nil)
            @br_tag = tag_sets[:br]
            @img_tag = tag_sets[:img]
            @inline_newline = tag_sets[:inline_newline]
            @whitespace_pattern = whitespace_pattern
            @style_resolver = style_resolver
          end

          def collect_segments(element, inherited_styles = {})
            element.children.flat_map { |child| segments_for(child, inherited_styles) }
          end

          def segments_from_children(children, inherited_styles = {})
            Array(children).flat_map { |child| segments_for(child, inherited_styles) }
          end

          def text_segment(text, styles = {})
            TextSegment.new(text: normalize_text(text.to_s, styles), styles: styles)
          end

          def image_placeholder_segment(inherited_styles, alt: nil)
            placeholder_segment(inherited_styles.merge(dim: true), alt)
          end

          def inline_image_placeholder_segment(element, inherited_styles)
            attrs = element.attributes
            alt = attrs['alt'].to_s.strip
            styles = inherited_styles.merge(
              dim: true,
              inline_image: { src: attrs['src'].to_s, alt: alt }
            )
            placeholder_segment(styles, alt)
          end

          # Inline styles derived from an element's style="" attribute. Public so
          # block builders can seed inherited styles for block-level elements.
          def style_attributes(element)
            style_attr = element.attributes['style'].to_s
            return {} if style_attr.empty?

            styles = SPAN_STYLE_MATCHERS.each_with_object({}) do |(key, matcher), acc|
              acc[key] = true if matcher.match?(style_attr)
            end
            apply_color_styles(styles, style_attr)
            styles
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
            return [] if SKIPPED_INLINE_ELEMENTS.include?(name)
            return [] if @style_resolver&.display_none?(element)
            return [line_break_segment(inherited_styles)] if name == @br_tag
            return [inline_image_placeholder_segment(element, inherited_styles)] if name == @img_tag

            new_styles = inherited_styles.merge(styles_for(name, element))
            collect_segments(element, new_styles)
          end

          def line_break_segment(inherited_styles)
            text_segment(@inline_newline, inherited_styles.merge(break: true))
          end

          def styles_for(name, element)
            base = STYLE_MAP[name] || {}
            css = @style_resolver ? @style_resolver.inline_styles(element) : {}
            base = base.merge(css) unless css.empty?
            base = base.merge(link_styles(element)) if name == 'a'
            base = base.merge(font_attribute_styles(element)) if name == 'font'
            attr_styles = style_attributes(element)
            attr_styles.empty? ? base : base.merge(attr_styles)
          end

          # Footnote references render as superscript marks even without CSS.
          def link_styles(element)
            styles = { link: element.attributes['href'] }
            styles[:superscript] = true if element.attributes['epub:type'].to_s.include?('noteref')
            styles
          end

          def font_attribute_styles(element)
            color = element.attributes['color'].to_s.strip
            color.empty? ? {} : { fg: color }
          end

          def apply_color_styles(styles, style_attr)
            fg = color_style_value(style_attr, COLOR_STYLE_PATTERN)
            bg = color_style_value(style_attr, BACKGROUND_STYLE_PATTERN)
            styles[:fg] = fg if fg
            styles[:bg] = bg if bg
          end

          def color_style_value(style_attr, pattern)
            match = pattern.match(style_attr)
            return nil unless match

            value = match[1].to_s.sub(/\s*!important\z/i, '').strip
            return nil if value.empty? || NON_COLOR_VALUES.include?(value.downcase)

            value
          end

          def normalize_text(text, styles)
            decoded = apply_transform(decode_text(text), styles)
            return decoded if preserve_whitespace?(styles)
            return normalize_break(decoded) if styles[:break]

            normalize_whitespace(decoded)
          end

          def apply_transform(text, styles)
            styles[:transform] == :upcase ? text.upcase : text
          end

          def decode_text(text)
            decoded = Shoko::Adapters::BookSources::Epub::HTMLProcessor.decode_entities(text)
            Shoko::Shared::TextSanitizer.sanitize(decoded, preserve_newlines: true, preserve_tabs: true)
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

          def placeholder_segment(styles, alt = nil)
            text_segment(" #{placeholder_text(alt)} ", styles)
          end

          def placeholder_text(alt)
            cleaned = alt.to_s.gsub(/\s+/, ' ').strip
            return PLACEHOLDER_TEXT if cleaned.empty?

            cleaned = "#{cleaned[0, MAX_ALT_LENGTH - 1]}…" if cleaned.length > MAX_ALT_LENGTH
            "[Image: #{cleaned}]"
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
