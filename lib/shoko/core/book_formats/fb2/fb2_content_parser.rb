# frozen_string_literal: true

require 'rexml/document'
require_relative '../../models/content_block'
require_relative 'fb2_inline_parser'

module Shoko
  module Core
    module BookFormats
      module Fb2
        # Parses an FB2 section XML fragment into an array of
        # {Core::Models::ContentBlock} objects — the same format produced by the
        # EPUB XHTML parser, so downstream formatting/rendering is reused unchanged.
        class Fb2ContentParser
          # @param raw_xml [String] raw XML of a single FB2 <section>
          # @param logger [Object, nil]
          def initialize(raw_xml, logger: nil)
            @raw_xml = raw_xml.to_s
            @logger = logger
            @blocks = []
          end

          # @return [Array<Core::Models::ContentBlock>]
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
            # Section fragments lack namespace declarations from the parent
            # <FictionBook> root (e.g., xmlns:l for XLink). Strip prefixes
            # from attributes so REXML can parse the fragment.
            cleaned = xml.gsub(/(<[^>]*?)\b\w+:(\w+=)/m, '\1\2')
            REXML::Document.new(cleaned)
          rescue REXML::ParseException => e
            @logger&.debug('FB2 XML parse error', error: e.message)
            nil
          end

          def process_children(element, depth:)
            element.each_child do |child|
              next unless child.is_a?(REXML::Element)

              process_element(child, depth: depth)
            end
          end

          def process_element(element, depth:)
            case element.name.to_s.downcase
            when 'p'           then process_paragraph(element)
            when 'title'       then process_title(element, depth: depth)
            when 'subtitle'    then process_subtitle(element)
            when 'image'       then process_image(element)
            when 'poem'        then process_poem(element)
            when 'cite'        then process_cite(element)
            when 'epigraph'    then process_epigraph(element)
            when 'table'       then process_table(element)
            when 'empty-line'  then process_empty_line
            when 'code'        then process_code(element)
            when 'annotation'  then process_children(element, depth: depth)
            when 'section'     then process_children(element, depth: depth + 1)
            end
          end

          def process_paragraph(element)
            segments = Fb2InlineParser.build_segments(element)
            return if segments.empty?

            @blocks << Core::Models::ContentBlock.new(
              type: :paragraph,
              segments: segments,
              level: 0,
              metadata: {}
            )
          end

          def process_title(element, depth:)
            # FB2 <title> contains <p> elements
            element.elements.each do |child|
              next unless child.name.to_s.downcase == 'p'

              segments = Fb2InlineParser.build_segments(child)
              next if segments.empty?

              @blocks << Core::Models::ContentBlock.new(
                type: :heading,
                segments: segments,
                level: [depth + 1, 1].max,
                metadata: { level: [depth + 1, 1].max, align: :center }
              )
            end
          end

          def process_subtitle(element)
            segments = Fb2InlineParser.build_segments(element)
            return if segments.empty?

            @blocks << Core::Models::ContentBlock.new(
              type: :heading,
              segments: segments,
              level: 3,
              metadata: { level: 3, align: :center }
            )
          end

          def process_image(element)
            href = element.attributes['l:href'] || element.attributes['href'] || ''
            # Strip leading # from internal references
            src = href.delete_prefix('#')
            alt = element.attributes['alt'] || element.attributes['title'] || ''

            placeholder = Core::Models::TextSegment.new(text: '[Image]', styles: { dim: true })
            @blocks << Core::Models::ContentBlock.new(
              type: :image,
              segments: [placeholder],
              level: 0,
              metadata: { image: { src: src, alt: alt } }
            )
          end

          def process_poem(element)
            # A poem contains <stanza> elements, each with <v> (verse) lines
            # and optionally <title>, <epigraph>, <text-author>
            element.each_child do |child|
              next unless child.is_a?(REXML::Element)

              case child.name.to_s.downcase
              when 'title'
                process_title(child, depth: 2)
              when 'stanza'
                process_stanza(child)
              when 'text-author'
                segments = Fb2InlineParser.build_segments(child)
                unless segments.empty?
                  @blocks << Core::Models::ContentBlock.new(
                    type: :paragraph,
                    segments: segments,
                    level: 0,
                    metadata: attribution_metadata
                  )
                end
              when 'epigraph'
                process_epigraph(child)
              end
            end
          end

          def process_stanza(stanza)
            stanza.elements.each do |child|
              next unless child.name.to_s.downcase == 'v'

              segments = Fb2InlineParser.build_segments(child)
              next if segments.empty?

              @blocks << Core::Models::ContentBlock.new(
                type: :quote,
                segments: segments,
                level: 1,
                metadata: { style: :verse }
              )
            end
          end

          def process_cite(element)
            element.each_child do |child|
              next unless child.is_a?(REXML::Element)

              case child.name.to_s.downcase
              when 'p'
                segments = Fb2InlineParser.build_segments(child)
                unless segments.empty?
                  @blocks << Core::Models::ContentBlock.new(
                    type: :quote,
                    segments: segments,
                    level: 1,
                    metadata: {}
                  )
                end
              when 'poem'
                process_poem(child)
              when 'text-author'
                segments = Fb2InlineParser.build_segments(child)
                unless segments.empty?
                  @blocks << Core::Models::ContentBlock.new(
                    type: :paragraph,
                    segments: segments,
                    level: 0,
                    metadata: attribution_metadata
                  )
                end
              when 'subtitle'
                process_subtitle(child)
              when 'empty-line'
                process_empty_line
              when 'table'
                process_table(child)
              end
            end
          end

          def process_epigraph(element)
            element.each_child do |child|
              next unless child.is_a?(REXML::Element)

              case child.name.to_s.downcase
              when 'p'
                segments = Fb2InlineParser.build_segments(child)
                unless segments.empty?
                  @blocks << Core::Models::ContentBlock.new(
                    type: :quote,
                    segments: italicize_segments(segments),
                    level: 1,
                    metadata: { style: :epigraph, align: :right }
                  )
                end
              when 'poem'
                process_poem(child)
              when 'cite'
                process_cite(child)
              when 'text-author'
                segments = Fb2InlineParser.build_segments(child)
                unless segments.empty?
                  @blocks << Core::Models::ContentBlock.new(
                    type: :paragraph,
                    segments: segments,
                    level: 0,
                    metadata: attribution_metadata
                  )
                end
              when 'empty-line'
                process_empty_line
              end
            end
          end

          def process_table(element)
            rows = []
            element.elements.each do |child|
              next unless child.name.to_s.downcase == 'tr'

              cells = []
              child.elements.each do |cell_el|
                cell_name = cell_el.name.to_s.downcase
                next unless %w[th td].include?(cell_name)

                text = Fb2InlineParser.plain_text(cell_el)
                cells << { text: text, header: cell_name == 'th' }
              end
              rows << cells unless cells.empty?
            end

            return if rows.empty?

            header_text = rows.map { |row| row.map { |c| c[:text] }.join(' | ') }.join("\n")
            segments = [Core::Models::TextSegment.new(text: header_text, styles: {})]

            @blocks << Core::Models::ContentBlock.new(
              type: :table,
              segments: segments,
              level: 0,
              metadata: { table: { rows: rows } }
            )
          end

          def process_code(element)
            text = Fb2InlineParser.plain_text(element)
            return if text.empty?

            segments = [Core::Models::TextSegment.new(text: text, styles: { code: true })]
            @blocks << Core::Models::ContentBlock.new(
              type: :code,
              segments: segments,
              level: 0,
              metadata: {}
            )
          end

          def process_empty_line
            @blocks << Core::Models::ContentBlock.new(
              type: :break,
              segments: [],
              level: 0,
              metadata: {}
            )
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
        end
      end
    end
  end
end
