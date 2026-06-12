# frozen_string_literal: true

require 'json'

require_relative '../../../../core/models/content_block'
require_relative 'pdf_layout_line_normalizer'
require_relative 'pdf_layout_payload_parser'
require_relative 'pdf_layout_classifier'

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Converts extracted PDF chapter payloads into semantic content blocks.
        class PdfContentParser
          # @param raw_text [String] text/layout payload extracted from PDF pages
          # @param logger [Object, nil]
          def initialize(raw_text, logger: nil)
            @raw_text = raw_text.to_s
            @logger = logger
            @line_normalizer = PdfLayoutLineNormalizer.new
            @payload_parser = PdfLayoutPayloadParser.new(line_normalizer: @line_normalizer)
            @layout_classifier = PdfLayoutClassifier.new
          end

          # @return [Array<Core::Models::ContentBlock>]
          def parse
            return [] if @raw_text.strip.empty?

            layout = parse_layout_payload(@raw_text)
            if layout
              blocks = parse_layout_blocks(layout)
              return blocks unless blocks.empty?
            end

            split_paragraphs(@raw_text).filter_map { |paragraph| build_paragraph_block(paragraph) }
          rescue Shoko::Error => e
            @logger&.debug('PDF content parse failed', error: e.message)
            fallback_blocks
          end

          private

          def parse_layout_payload(text)
            @payload_parser.parse(text)
          end

          def parse_layout_blocks(layout)
            lines = @line_normalizer.normalize_lines(layout[:lines])
            return [] if lines.empty?

            metrics = @layout_classifier.line_metrics(lines)
            groups = @layout_classifier.build_groups(lines, metrics)
            groups.flat_map { |group| blocks_for_group(group) }
          end

          def blocks_for_group(group)
            case group[:kind]
            when :heading
              [build_heading_block(group[:lines])]
            when :epigraph
              build_epigraph_blocks(group[:lines], align: group[:align])
            else
              [build_paragraph_from_lines(group[:lines], align: group[:align])]
            end.compact
          end

          def build_heading_block(lines)
            text = lines.map { |line| line[:text] }.join(' ').strip
            return nil if text.empty?

            Core::Models::ContentBlock.new(
              type: :heading,
              segments: [Core::Models::TextSegment.new(text: text, styles: {})],
              level: 1,
              metadata: { level: 1, align: :center }
            )
          end

          def build_epigraph_blocks(lines, align:)
            return [] if lines.empty?

            quote_lines, attribution = split_epigraph_attribution(lines)
            blocks = [build_epigraph_quote_block(quote_lines, align: align)].compact
            return blocks unless attribution

            blocks << attribution_block(attribution)
            blocks
          end

          def split_epigraph_attribution(lines)
            quote_lines = lines.dup
            return [quote_lines, nil] unless quote_lines.length > 1
            return [quote_lines, nil] unless @layout_classifier.attribution_signature_line?(quote_lines.last[:text])

            [quote_lines[0...-1], quote_lines.last]
          end

          def attribution_block(line)
            Core::Models::ContentBlock.new(
              type: :paragraph,
              segments: [Core::Models::TextSegment.new(text: line[:text], styles: {})],
              level: 0,
              metadata: { style: :attribution, align: :right }
            )
          end

          def build_epigraph_quote_block(lines, align:)
            return nil if lines.empty?

            segments = quote_segments(lines)
            Core::Models::ContentBlock.new(
              type: :quote,
              segments: segments,
              level: 1,
              metadata: { style: :epigraph, align: normalize_epigraph_align(align) }
            )
          end

          def quote_segments(lines)
            force_italic = lines.none? { |line| line[:italic] }
            lines.each_with_index.flat_map do |line, idx|
              style = {}
              style[:italic] = true if force_italic || line[:italic]
              segment = Core::Models::TextSegment.new(text: line[:text], styles: style)
              idx >= lines.length - 1 ? [segment] : [segment, newline_segment(style)]
            end
          end

          def newline_segment(style)
            Core::Models::TextSegment.new(text: "\n", styles: style)
          end

          def normalize_epigraph_align(align)
            return :center if align == :center

            :right
          end

          def build_paragraph_from_lines(lines, align:)
            text = lines.map { |line| line[:text] }.join(' ').gsub(/\s+/, ' ').strip
            return nil if text.empty?

            metadata = {}
            metadata[:align] = align if align && align != :left
            Core::Models::ContentBlock.new(
              type: :paragraph,
              segments: [Core::Models::TextSegment.new(text: text, styles: {})],
              level: 0,
              metadata: metadata
            )
          end

          def split_paragraphs(text)
            text.split(/\n{2,}/).map do |paragraph|
              paragraph.tr("\n", ' ').gsub(/\s+/, ' ').strip
            end.reject(&:empty?)
          end

          def build_paragraph_block(text)
            return nil if text.empty?

            segments = [Core::Models::TextSegment.new(text: text, styles: {})]
            Core::Models::ContentBlock.new(type: :paragraph, segments: segments, level: 0, metadata: {})
          end

          def fallback_blocks
            text = @raw_text.gsub(/\s+/, ' ').strip
            return [] if text.empty?

            [Core::Models::ContentBlock.new(
              type: :paragraph,
              segments: [Core::Models::TextSegment.new(text: text, styles: {})],
              level: 0,
              metadata: {}
            )]
          end
        end
      end
    end
  end
end
