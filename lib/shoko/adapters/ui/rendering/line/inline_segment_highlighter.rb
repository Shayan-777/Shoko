# frozen_string_literal: true

require_relative '../../../../core/models/content_block'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Applies inline quote/keyword highlighting to a list of TextSegment objects.
          #
          # This is used for DisplayLine rendering where segments already carry style metadata.
          module InlineSegmentHighlighter
            module_function

            def apply(segments, block_type:, highlight_quotes:, highlight_keywords:)
              return segments unless highlightable?(segments, block_type, highlight_quotes, highlight_keywords)

              text = segments_text(segments)
              return segments if text.empty?

              quote_ranges, keyword_ranges = build_ranges(text, highlight_quotes, highlight_keywords)
              return segments if quote_ranges.empty? && keyword_ranges.empty?

              applicator = RangeApplicator.new(text: text, quote_ranges: quote_ranges, keyword_ranges: keyword_ranges)
              applicator.apply_to_segments(segments)
            rescue Shoko::Error
              segments
            end

            def match_ranges(text, pattern)
              ranges = []
              text.to_enum(:scan, pattern).each do
                match = Regexp.last_match
                next unless match

                start_index = match.begin(0)
                end_index = match.end(0)
                ranges << (start_index...end_index) if end_index > start_index
              end
              ranges
            rescue Shoko::Error
              []
            end

            def in_ranges?(index, ranges)
              return false if ranges.empty?

              idx = index.to_i
              lo = 0
              hi = ranges.length - 1
              while lo <= hi
                mid = (lo + hi) / 2
                range = ranges[mid]
                return true if idx >= range.begin && idx < range.end

                idx < range.begin ? hi = mid - 1 : lo = mid + 1
              end
              false
            rescue Shoko::Error
              false
            end

            def segments_text(segments)
              segments.map { |segment| segment&.text.to_s }.join
            end

            private

            def highlightable?(segments, block_type, highlight_quotes, highlight_keywords)
              return false unless highlight_quotes || highlight_keywords
              return false if segments.empty?

              block_type != :code
            end

            def build_ranges(text, highlight_quotes, highlight_keywords)
              quote_ranges = if highlight_quotes
                               match_ranges(text,
                                            Shoko::Adapters::Ui::Constants::Highlighting::QUOTE_PATTERNS)
                             else
                               []
                             end
              keyword_ranges = if highlight_keywords
                                 match_ranges(text,
                                              Shoko::Adapters::Ui::Constants::Highlighting::HIGHLIGHT_PATTERNS)
                               else
                                 []
                               end
              [quote_ranges, keyword_ranges]
            end

            module_function :highlightable?, :build_ranges
            private_class_method :highlightable?, :build_ranges

            # Applies computed range boundaries to segments and emits new TextSegment objects.
            class RangeApplicator
              def initialize(text:, quote_ranges:, keyword_ranges:)
                @text = text
                @quote_ranges = quote_ranges
                @keyword_ranges = keyword_ranges
              end

              def apply_to_segments(segments)
                output = []
                offset = 0

                segments.each do |segment|
                  seg_text = segment.text.to_s
                  seg_start = offset
                  seg_end = seg_start + seg_text.length
                  offset = seg_end
                  next if seg_text.empty?

                  base_styles = segment.styles || {}
                  boundaries = boundaries_for_segment(seg_start, seg_end, base_styles)
                  output.concat(segment_pieces(boundaries, base_styles))
                end

                output
              end

              private

              attr_reader :text, :quote_ranges, :keyword_ranges

              def boundaries_for_segment(seg_start, seg_end, base_styles)
                boundaries = [seg_start, seg_end]
                return boundaries if base_styles[:code]

                (quote_ranges + keyword_ranges).each do |range|
                  add_boundary(boundaries, range.begin, seg_start, seg_end)
                  add_boundary(boundaries, range.end, seg_start, seg_end)
                end

                boundaries.sort.uniq
              end

              def add_boundary(boundaries, value, seg_start, seg_end)
                boundaries << value if value > seg_start && value < seg_end
              end

              def segment_pieces(boundaries, base_styles)
                boundaries.each_cons(2).filter_map do |start_index, end_index|
                  next if start_index >= end_index

                  piece = text[start_index...end_index].to_s
                  next if piece.empty?

                  styles = styles_for_piece(base_styles, start_index)
                  Shoko::Core::Models::TextSegment.new(text: piece, styles: styles)
                end
              end

              def styles_for_piece(base_styles, index)
                return base_styles if base_styles[:code]

                styles = base_styles
                styles = styles.merge(quote: true) if InlineSegmentHighlighter.in_ranges?(index, quote_ranges)
                styles = styles.merge(accent: true) if InlineSegmentHighlighter.in_ranges?(index, keyword_ranges)
                styles
              end
            end
          end
        end
      end
    end
  end
end
