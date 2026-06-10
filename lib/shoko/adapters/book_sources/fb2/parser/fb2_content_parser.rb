# frozen_string_literal: true

require 'rexml/document'
require_relative '../../../../core/models/content_block'
require_relative 'fb2_inline_parser'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Parses an FB2 section fragment into the common ContentBlock representation.
        class Fb2ContentParser
          ELEMENT_HANDLERS = {
            'p' => :process_paragraph,
            'title' => :process_title,
            'subtitle' => :process_subtitle,
            'image' => :process_image,
            'poem' => :process_poem,
            'cite' => :process_cite,
            'epigraph' => :process_epigraph,
            'table' => :process_table,
            'empty-line' => :process_empty_line,
            'code' => :process_code,
          }.freeze

          def initialize(raw_xml, logger: nil)
            @raw_xml = raw_xml.to_s
            @logger = logger
            @blocks = []
          end

          def parse
            doc = safe_parse(@raw_xml)
            return fallback_blocks unless doc

            root = doc.root || doc
            process_children(root, depth: 0)
            @blocks.empty? ? fallback_blocks : @blocks
          rescue Shoko::Error => e
            @logger&.debug('FB2 content parse failed', error: e.message)
            fallback_blocks
          end

          private

          def safe_parse(xml)
            REXML::Document.new(xml)
          rescue REXML::UndefinedNamespaceException
            cleaned = xml.gsub(/(<[^>]*?)\b\w+:(\w+=)/m, '\1\2')
            REXML::Document.new(cleaned)
          rescue REXML::ParseException => e
            @logger&.debug('FB2 XML parse error', error: e.message)
            nil
          end

          def process_children(element, depth:)
            each_element_child(element) { |child| process_element(child, depth: depth) }
          end

          def process_element(element, depth:)
            name = element_name(element)
            return process_children(element, depth: depth) if name == 'annotation'
            return process_children(element, depth: depth + 1) if name == 'section'

            handler = ELEMENT_HANDLERS[name]
            return unless handler

            dispatch_handler(handler, element, depth: depth)
          end

          def dispatch_handler(handler, element, depth:)
            parameters = method(handler).parameters
            args = accepts_positional_argument?(parameters) ? [element] : []
            kwargs = accepts_depth_keyword?(parameters) ? { depth: depth } : {}
            send(handler, *args, **kwargs)
          end

          def accepts_positional_argument?(parameters)
            parameters.any? { |kind, _name| %i[req opt rest].include?(kind) }
          end

          def accepts_depth_keyword?(parameters)
            parameters.any? do |kind, name|
              %i[key keyreq keyrest].include?(kind) && name == :depth
            end
          end

          def process_paragraph(element)
            segments = Fb2InlineParser.build_segments(element)
            return if segments.empty?

            append_block(:paragraph, segments)
          end

          def process_title(element, depth:)
            level = [depth + 1, 1].max
            each_element_child(element) do |child|
              next unless element_name(child) == 'p'

              segments = Fb2InlineParser.build_segments(child)
              next if segments.empty?

              append_block(:heading, segments, level: level, metadata: { level: level, align: :center })
            end
          end

          def process_subtitle(element)
            segments = Fb2InlineParser.build_segments(element)
            return if segments.empty?

            append_block(:heading, segments, level: 3, metadata: { level: 3, align: :center })
          end

          def process_image(element)
            href = element.attributes['l:href'] || element.attributes['href'] || ''
            src = href.delete_prefix('#')
            alt = element.attributes['alt'] || element.attributes['title'] || ''
            placeholder = Core::Models::TextSegment.new(text: '[Image]', styles: { dim: true })

            append_block(:image, [placeholder], metadata: { image: { src: src, alt: alt } })
          end

          def process_code(element)
            text = Fb2InlineParser.plain_text(element)
            return if text.empty?

            segments = [Core::Models::TextSegment.new(text: text, styles: { code: true })]
            append_block(:code, segments)
          end

          def process_empty_line
            append_block(:break, [])
          end

          def fallback_blocks
            text = @raw_xml.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
            return [] if text.empty?

            [Core::Models::ContentBlock.new(
              type: :paragraph,
              segments: [Core::Models::TextSegment.new(text: text, styles: {})],
              level: 0,
              metadata: {}
            )]
          end

          def italicize_segments(segments)
            Array(segments).map do |segment|
              styles = (segment.styles || {}).merge(italic: true)
              Core::Models::TextSegment.new(text: segment.text.to_s, styles: styles)
            end
          end

          def attribution_metadata
            { style: :attribution, align: :right }
          end

          def each_element_child(element)
            return enum_for(:each_element_child, element) unless block_given?

            element.each_child do |child|
              yield child if child.is_a?(REXML::Element)
            end
          end

          def element_name(element)
            element.name.to_s.downcase
          end

          def append_attribution_block(element)
            segments = Fb2InlineParser.build_segments(element)
            return if segments.empty?

            append_block(:paragraph, segments, metadata: attribution_metadata)
          end

          def append_quote_block(segments, metadata: {})
            return if segments.empty?

            append_block(:quote, segments, level: 1, metadata: metadata)
          end

          def append_block(type, segments, level: 0, metadata: {})
            @blocks << Core::Models::ContentBlock.new(
              type: type,
              segments: segments,
              level: level,
              metadata: metadata
            )
          end

          def process_poem(element)
            each_element_child(element) { |child| process_poem_child(child) }
          end

          def process_poem_child(child)
            case element_name(child)
            when 'title'
              process_title(child, depth: 2)
            when 'stanza'
              process_stanza(child)
            when 'text-author'
              append_attribution_block(child)
            when 'epigraph'
              process_epigraph(child)
            end
          end

          def process_stanza(stanza)
            each_element_child(stanza) do |child|
              next unless element_name(child) == 'v'

              append_quote_block(Fb2InlineParser.build_segments(child), metadata: { style: :verse })
            end
          end

          def process_cite(element)
            process_quote_container(element, epigraph: false)
          end

          def process_epigraph(element)
            process_quote_container(element, epigraph: true)
          end

          def process_quote_container(element, epigraph:)
            each_element_child(element) { |child| process_quote_child(child, epigraph: epigraph) }
          end

          def process_quote_child(child, epigraph:)
            name = element_name(child)
            return append_quote_paragraph(child, epigraph: epigraph) if name == 'p'

            process_nested_quote_child(child, name, epigraph: epigraph)
          end

          def append_quote_paragraph(element, epigraph:)
            segments = Fb2InlineParser.build_segments(element)
            return if segments.empty?

            segments = italicize_segments(segments) if epigraph
            metadata = epigraph ? { style: :epigraph, align: :right } : {}
            append_quote_block(segments, metadata: metadata)
          end

          def process_nested_quote_child(child, name, epigraph:)
            return process_epigraph_quote_child(child, name) if epigraph

            process_standard_quote_child(child, name)
          end

          def process_standard_quote_child(child, name)
            case name
            when 'poem'
              process_poem(child)
            when 'text-author'
              append_attribution_block(child)
            when 'subtitle'
              process_subtitle(child)
            when 'empty-line'
              process_empty_line
            when 'table'
              process_table(child)
            end
          end

          def process_epigraph_quote_child(child, name)
            case name
            when 'poem'
              process_poem(child)
            when 'cite'
              process_cite(child)
            when 'text-author'
              append_attribution_block(child)
            when 'empty-line'
              process_empty_line
            end
          end

          def process_table(element)
            rows = table_rows(element)
            return if rows.empty?

            table_text = rows.map { |row| row.map { |cell| cell[:text] }.join(' | ') }.join("\n")
            segments = [Core::Models::TextSegment.new(text: table_text, styles: {})]
            append_block(:table, segments, metadata: { table: { rows: rows } })
          end

          def table_rows(element)
            rows = []
            each_element_child(element) do |child|
              next unless element_name(child) == 'tr'

              cells = table_cells(child)
              rows << cells unless cells.empty?
            end
            rows
          end

          def table_cells(row_element)
            each_element_child(row_element).filter_map do |cell|
              name = element_name(cell)
              next unless %w[th td].include?(name)

              { text: Fb2InlineParser.plain_text(cell), header: name == 'th' }
            end
          end
        end
      end
    end
  end
end
