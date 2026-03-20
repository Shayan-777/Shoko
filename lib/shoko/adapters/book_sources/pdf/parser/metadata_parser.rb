# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Canonical parser for PDF metadata fields.
        class MetadataParser
          ESCAPED_LITERALS = {
            0x6E => "\n".b,
            0x72 => "\r".b,
            0x74 => "\t".b,
            0x62 => "\b".b,
            0x66 => "\f".b,
            0x28 => '('.b,
            0x29 => ')'.b,
            0x5C => '\\'.b,
          }.freeze

          class << self
            # @param info [Hash, nil] Raw info dictionary values
            # @return [Hash] canonical metadata hash
            def parse(info = nil, **kwargs)
              payload = normalize_payload(info, kwargs)
              title = normalize_text(payload[:title])
              author = normalize_text(payload[:author])
              year = extract_year(payload[:creation_date])

              {
                title: title,
                authors: author ? [author] : [],
                year: year,
                language: nil,
              }
            end

            private

            def normalize_payload(info, kwargs)
              source = info.is_a?(Hash) ? info : {}
              symbolize_keys(source).merge(kwargs)
            end

            def symbolize_keys(hash)
              hash.transform_keys(&:to_sym)
            end

            def normalize_text(value)
              return nil unless value

              text = decode_text(value).strip
              text.empty? ? nil : text
            end

            def extract_year(value)
              return nil unless value

              match = value.to_s.match(/(\d{4})/)
              match && match[1]
            end

            def decode_text(value)
              raw = value.to_s
              bytes = hex_encoded?(raw) ? hex_bytes(raw) : unescape_literal_bytes(raw)

              decode_bytes(bytes)
            rescue ArgumentError, EncodingError
              safe_utf8(raw)
            end

            def hex_encoded?(text)
              text.match?(/\A(?:[0-9A-Fa-f]{2}\s*)+\z/)
            end

            def hex_bytes(text)
              [text.delete(" \t\r\n")].pack('H*').force_encoding(Encoding::BINARY)
            end

            def unescape_literal_bytes(text)
              source = text.dup
              source.force_encoding(Encoding::BINARY)

              output = String.new(capacity: source.bytesize)
              output.force_encoding(Encoding::BINARY)

              index = 0
              while index < source.bytesize
                byte = source.getbyte(index)
                if byte == 0x5C
                  index = append_escaped_byte(source, index + 1, output)
                else
                  output << byte
                  index += 1
                end
              end

              output
            end

            def append_escaped_byte(source, index, output)
              return index if index >= source.bytesize

              byte = source.getbyte(index)
              return line_continuation_index(source, index) if line_continuation_byte?(byte)
              return append_octal_escape(source, index, output) if octal_digit?(byte)

              output << escaped_literal(byte)
              index + 1
            end

            def append_octal_escape(source, index, output)
              digits = +source.getbyte(index).chr
              cursor = index + 1
              while cursor < source.bytesize && digits.length < 3
                byte = source.getbyte(cursor)
                break unless byte.between?(0x30, 0x37)

                digits << byte.chr
                cursor += 1
              end

              output << digits.to_i(8)
              cursor
            end

            def decode_bytes(bytes)
              data = binary_string(bytes)
              return decode_utf16(data, Encoding::UTF_16BE, drop_bom: true) if data.start_with?("\xFE\xFF".b)
              return decode_utf16(data, Encoding::UTF_16LE, drop_bom: true) if data.start_with?("\xFF\xFE".b)
              return decode_utf16(data, Encoding::UTF_16BE) if utf16_without_bom?(data)

              safe_utf8(data)
            end

            def line_continuation_byte?(byte)
              [0x0A, 0x0D].include?(byte)
            end

            def line_continuation_index(source, index)
              return index + 2 if source.getbyte(index) == 0x0D && source.getbyte(index + 1) == 0x0A

              index + 1
            end

            def octal_digit?(byte)
              byte.between?(0x30, 0x37)
            end

            def escaped_literal(byte)
              ESCAPED_LITERALS.fetch(byte) { binary_char(byte) }
            end

            def binary_char(byte)
              String.new(encoding: Encoding::BINARY) << byte
            end

            def binary_string(text)
              text.dup.force_encoding(Encoding::BINARY)
            end

            def utf16_without_bom?(data)
              data.include?("\x00".b) && data.bytesize.even?
            end

            def decode_utf16(data, encoding, drop_bom: false)
              payload = drop_bom ? data.byteslice(2..) : data
              return '' unless payload

              payload.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
            end

            def safe_utf8(text)
              utf8 = text.dup.force_encoding(Encoding::UTF_8)
              return utf8 if utf8.valid_encoding?

              utf8.scrub('')
            end
          end
        end
      end
    end
  end
end
