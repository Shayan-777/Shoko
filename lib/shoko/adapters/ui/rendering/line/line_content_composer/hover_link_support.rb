# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Hover-link helpers for splitting and styling inline-link segments.
          module LineContentComposerHoverLinkSupport
            HoverLink = Data.define(:line_offset, :start_char, :end_char, :href)

            private

            def hover_signature_for(hovered_inline_link, line_offset)
              hover = active_hover_link(hovered_inline_link, line_offset)
              hover && [hover.line_offset, hover.start_char, hover.end_char, hover.href]
            end

            def apply_hover_link_style(segments, line_offset:, hovered_inline_link:)
              hover = active_hover_link(hovered_inline_link, line_offset)
              return segments unless hover

              cursor = 0
              segments.each_with_object([]) do |segment, output|
                text = segment&.text.to_s
                next if text.empty?

                output.concat(split_hovered_segment(segment, text, seg_start: cursor, hover: hover))
                cursor += text.length
              end
            end

            def active_hover_link(hovered_inline_link, line_offset)
              hover = normalize_hovered_inline_link(hovered_inline_link)
              return nil unless hover
              return nil unless line_offset.to_i == hover.line_offset

              hover
            end

            def split_hovered_segment(segment, text, seg_start:, hover:)
              seg_end = seg_start + text.length
              hover_boundaries(seg_start, seg_end, hover).each_cons(2).filter_map do |piece_start, piece_end|
                hovered_segment_piece(
                  piece_start: piece_start,
                  piece_end: piece_end,
                  seg_start: seg_start,
                  text: text,
                  styles: segment.styles || {},
                  hover: hover
                )
              end
            end

            def hover_boundaries(seg_start, seg_end, hover)
              [seg_start, seg_end, hover.start_char, hover.end_char].grep(seg_start..seg_end).uniq.sort
            end

            def hovered_segment_piece(piece_start:, piece_end:, seg_start:, text:, styles:, hover:)
              return nil if piece_end <= piece_start

              piece = text[(piece_start - seg_start)...(piece_end - seg_start)].to_s
              return nil if piece.empty?

              Shoko::Core::Models::TextSegment.new(
                text: piece,
                styles: hover_styles(styles, hover, piece_start, piece_end)
              )
            end

            def hover_styles(styles, hover, piece_start, piece_end)
              return styles unless hover_overlap?(hover, piece_start, piece_end)
              return styles unless link_matches_hover?(styles, hover.href)

              styles.merge(link_hover: true)
            end

            def hover_overlap?(hover, piece_start, piece_end)
              piece_start < hover.end_char && piece_end > hover.start_char
            end

            def link_matches_hover?(styles, hover_href)
              link = styles[:link]
              return false if link.nil?

              link.to_s.strip == hover_href.to_s
            end

            def normalize_hovered_inline_link(value)
              return nil unless value.is_a?(Hash)

              normalized = symbolize_hash(value)
              start_char = normalized[:start_char].to_i
              end_char = normalized[:end_char].to_i
              href = normalized[:href].to_s.strip
              return nil if href.empty? || end_char <= start_char

              HoverLink.new(
                line_offset: normalized[:line_offset].to_i,
                start_char: start_char,
                end_char: end_char,
                href: href
              )
            end
          end
        end
      end
    end
  end
end
