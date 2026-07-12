# frozen_string_literal: true

require 'rexml/document'

require 'shoko/core/models/content_block'
require_relative 'list_marker'

module Shoko
  module Adapters
    module BookSources
      module Epub
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
      end
    end
  end
end
