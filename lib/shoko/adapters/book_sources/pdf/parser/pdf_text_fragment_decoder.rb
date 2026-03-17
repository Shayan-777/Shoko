# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Decodes PDF string operands and TJ arrays into UTF-8 text.
        class PdfTextFragmentDecoder
          WINDOWS_1252 = Encoding.find('Windows-1252')
          SIMPLE_ESCAPE_BYTES = {
            'n' => "\n".b,
            'r' => "\r".b,
            't' => "\t".b,
            'b' => "\b".b,
            'f' => "\f".b,
          }.freeze

          def decode_hex_string(hex, cmap, byte_map: nil, base_encoding: nil)
            clean_hex = hex.gsub(/\s+/, '')
            bytes = [clean_hex].pack('H*')
            if font_encoded_bytes?(byte_map, base_encoding)
              return decode_font_encoded_bytes(bytes, cmap, byte_map: byte_map, base_encoding: base_encoding)
            end

            return hex_fallback(hex) unless cmap

            text = +''
            idx = 0
            while idx < clean_hex.length
              char, step = mapped_glyph(clean_hex, idx, cmap)
              text << char if char
              idx += step
            end
            text
          end

          def decode_literal_string(str, cmap = nil, byte_map: nil, base_encoding: nil)
            bytes = decode_literal_bytes(str.to_s)
            if font_encoded_bytes?(byte_map, base_encoding)
              return decode_font_encoded_bytes(bytes, cmap, byte_map: byte_map, base_encoding: base_encoding)
            end

            return literal_bytes_fallback(bytes) unless cmap

            mapped = decode_hex_string(bytes.unpack1('H*'), cmap)
            mapped.empty? ? literal_bytes_fallback(bytes) : mapped
          end

          def decode_tj_array(array_content, cmap, byte_map: nil, base_encoding: nil)
            text = +''
            array_content.scan(/<([0-9a-fA-F\s]+)>|(\([^)]*\))|(-?[\d.]+)/).each do |hex, literal, num|
              if hex
                text << decode_hex_string(hex, cmap, byte_map: byte_map, base_encoding: base_encoding)
              elsif literal
                text << decode_literal_string(literal[1..-2], cmap, byte_map: byte_map, base_encoding: base_encoding)
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

          def decode_literal_bytes(str)
            bytes = +''
            bytes.force_encoding(Encoding::BINARY)
            index = 0

            while index < str.bytesize
              byte = str.getbyte(index)
              if byte == 0x5C
                decoded, index = consume_escape_sequence(str, index + 1)
                bytes << decoded
              else
                bytes << byte
                index += 1
              end
            end

            bytes
          end

          def consume_escape_sequence(str, index)
            return ['\\'.b, index] if index >= str.bytesize

            char = str.getbyte(index).chr
            return octal_escape(str, index) if char.match?(/[0-7]/)

            line_continuation_escape(str, index, char) || simple_escape(char, index)
          end

          def octal_escape_bytes(str, index)
            octal = str.byteslice(index, 3).to_s[/\A[0-7]{1,3}/]
            [octal.to_i(8)].pack('C')
          end

          def skip_octal_digits(str, index)
            octal = str.byteslice(index, 3).to_s[/\A[0-7]{1,3}/]
            index + octal.length
          end

          def octal_escape(str, index)
            [octal_escape_bytes(str, index), skip_octal_digits(str, index)]
          end

          def line_continuation_escape(str, index, char)
            return [''.b, index + 1] if char == "\n"
            return unless char == "\r"

            next_index = index + 1
            next_index += 1 if str.getbyte(next_index) == 0x0A
            [''.b, next_index]
          end

          def simple_escape(char, index)
            return [char.b, index + 1] if ['(', ')', '\\'].include?(char)

            [SIMPLE_ESCAPE_BYTES.fetch(char, char.b), index + 1]
          end

          def hex_fallback(hex)
            literal_bytes_fallback([hex].pack('H*'))
          end

          def font_encoded_bytes?(byte_map, base_encoding)
            (byte_map && !byte_map.empty?) || base_encoding == 'WinAnsiEncoding'
          end

          def decode_font_encoded_bytes(bytes, cmap, byte_map:, base_encoding:)
            bytes.each_byte.with_object(+'') do |byte, text|
              text << decode_font_encoded_byte(byte, cmap, byte_map: byte_map, base_encoding: base_encoding)
            end
          end

          def decode_font_encoded_byte(byte, cmap, byte_map:, base_encoding:)
            return byte_map[byte] if byte_map&.key?(byte)

            base_char = base_encoded_byte(byte, base_encoding)
            return base_char if base_char

            mapped = cmap && cmap[byte]
            return mapped if mapped

            literal_bytes_fallback([byte].pack('C'))
          end

          def base_encoded_byte(byte, base_encoding)
            return nil unless base_encoding == 'WinAnsiEncoding'
            return nil if byte < 0x20 && ![0x09, 0x0A, 0x0D].include?(byte)
            return nil if byte == 0x7F

            char = [byte]
              .pack('C')
              .force_encoding(WINDOWS_1252)
              .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')

            char.empty? ? nil : char
          end

          def literal_bytes_fallback(bytes)
            bytes.dup.force_encoding(Encoding::UTF_8)
                 .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
          rescue EncodingError
            bytes.dup.force_encoding(Encoding::UTF_8).scrub('')
          end
        end
      end
    end
  end
end
