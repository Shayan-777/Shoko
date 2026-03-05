# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Decodes PDF string operands and TJ arrays into UTF-8 text.
        class PdfTextFragmentDecoder
          def decode_hex_string(hex, cmap)
            return hex_fallback(hex) unless cmap

            text = +''
            idx = 0
            clean_hex = hex.gsub(/\s+/, '')
            while idx < clean_hex.length
              char, step = mapped_glyph(clean_hex, idx, cmap)
              text << char if char
              idx += step
            end
            text
          end

          def decode_literal_string(str)
            str.to_s
               .gsub('\\n', "\n")
               .gsub('\\r', "\r")
               .gsub('\\t', "\t")
               .gsub('\\(', '(')
               .gsub('\\)', ')')
               .gsub('\\\\', '\\')
          end

          def decode_tj_array(array_content, cmap)
            text = +''
            array_content.scan(/<([0-9a-fA-F\s]+)>|(\([^)]*\))|(-?[\d.]+)/).each do |hex, literal, num|
              if hex
                text << decode_hex_string(hex, cmap)
              elsif literal
                text << decode_literal_string(literal[1..-2])
              elsif num
                text << ' ' if num.to_f < -100
              end
            end
            text
          end

          private

          def mapped_glyph(clean_hex, idx, cmap)
            four = mapped_glyph_for_width(clean_hex, idx, cmap, 4)
            return [four, 4] if four

            two = mapped_glyph_for_width(clean_hex, idx, cmap, 2)
            return [two, 2] if two

            [nil, 4]
          end

          def mapped_glyph_for_width(clean_hex, idx, cmap, width)
            return nil unless idx + width <= clean_hex.length

            glyph_id = clean_hex[idx, width].to_i(16)
            cmap[glyph_id]
          end

          def hex_fallback(hex)
            [hex].pack('H*').force_encoding('UTF-8')
          end
        end
      end
    end
  end
end
