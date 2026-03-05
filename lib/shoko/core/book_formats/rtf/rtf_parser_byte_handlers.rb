# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Rtf
        # Byte-level parsing helpers for control symbols, escapes, and plain text.
        module RtfParserByteHandlers
          private

          def handle_backslash
            @pos += 1
            return if @pos >= @len

            symbol = @rtf.getbyte(@pos)
            return handle_hex_escape if symbol == 39
            return handle_literal_symbol(symbol) if literal_symbol?(symbol)

            control_handler = control_symbol_handlers[symbol]
            return control_handler.call if control_handler
            return read_control_word if letter_byte?(symbol)

            @pos += 1
          end

          def control_symbol_handlers
            @control_symbol_handlers ||= {
              42 => method(:mark_next_destination_ignorable),
              126 => method(:append_nonbreaking_space),
              45 => method(:skip_optional_hyphen),
              95 => method(:append_nonbreaking_hyphen),
            }
          end

          def handle_hex_escape
            @pos += 1
            return if @pos + 1 >= @len

            hex = @rtf[@pos, 2]
            @pos += 2
            return if @skip_depth.positive?

            append_hex_escape_byte(hex.to_i(16))
          rescue ArgumentError, RangeError, Encoding::CompatibilityError,
                 Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            # Skip malformed hex escapes
          end

          def handle_literal_symbol(symbol)
            if @skip_depth.positive?
              @pos += 1
              return
            end

            append_char(symbol.chr)
            @pos += 1
          end

          def mark_next_destination_ignorable
            @pos += 1
            @ignorable_next = true
          end

          def append_nonbreaking_space
            @pos += 1
            append_char("\u00A0") unless @skip_depth.positive?
          end

          def skip_optional_hyphen
            @pos += 1
          end

          def append_nonbreaking_hyphen
            @pos += 1
            append_char("\u2011") unless @skip_depth.positive?
          end

          def read_control_word
            word = read_control_word_token
            param = read_optional_control_param
            consume_control_word_delimiter
            dispatch_control_word(word, param)
          end

          def read_control_word_token
            start = @pos
            @pos += 1 while @pos < @len && letter_byte?(@rtf.getbyte(@pos))
            @rtf[start...@pos]
          end

          def read_optional_control_param
            return nil unless signed_number_start?(@pos)

            start = @pos
            @pos += 1 if @rtf.getbyte(@pos) == 45
            @pos += 1 while @pos < @len && digit_byte?(@rtf.getbyte(@pos))
            @rtf[start...@pos].to_i
          end

          def consume_control_word_delimiter
            @pos += 1 if @pos < @len && @rtf.getbyte(@pos) == 32
          end

          def signed_number_start?(index)
            return false unless index < @len

            byte = @rtf.getbyte(index)
            byte == 45 || digit_byte?(byte)
          end

          def letter_byte?(byte)
            return false unless byte

            byte.between?(65, 90) || byte.between?(97, 122)
          end

          def digit_byte?(byte)
            byte&.between?(48, 57)
          end

          def literal_symbol?(byte)
            [123, 125, 92].include?(byte)
          end

          def append_hex_escape_byte(byte_val)
            return append_font_name_hex_byte(byte_val) if @in_fonttbl && @fonttbl_depth.positive?
            return @colortbl_text << byte_val.chr if @in_colortbl
            return append_info_hex_byte(byte_val) if @in_info && @info_field

            append_char(decode_codepage_byte(byte_val))
          end

          def append_font_name_hex_byte(byte_val)
            @current_font_name << decode_codepage_byte(byte_val)
          end

          def append_info_hex_byte(byte_val)
            @info_text << decode_codepage_byte(byte_val)
          end

          def decode_codepage_byte(byte_val)
            byte_val.chr(codepage_encoding).encode(
              'UTF-8',
              invalid: :replace,
              undef: :replace,
              replace: ''
            )
          end

          def handle_unicode(param)
            return if param.nil? || @skip_depth.positive?

            append_unicode_codepoint(param)
            skip_unicode_fallback_bytes
          rescue ArgumentError, RangeError, Encoding::CompatibilityError
            skip_unicode_fallback_bytes
          end

          def append_unicode_codepoint(param)
            codepoint = param.negative? ? param + 65_536 : param
            return unless valid_unicode_codepoint?(codepoint)

            append_char([codepoint].pack('U'))
          end

          def handle_plain_byte(byte)
            @pos += 1
            return if @skip_depth.positive?
            return handle_font_table_plain_byte(byte) if @in_fonttbl && @fonttbl_depth.positive?
            return handle_color_table_plain_byte(byte) if @in_colortbl
            return handle_info_plain_byte(byte) if @in_info && @info_field

            @current_text << decode_codepage_byte(byte)
          rescue ArgumentError, RangeError, Encoding::CompatibilityError,
                 Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            append_fallback_byte(byte)
          end

          def handle_font_table_plain_byte(byte)
            char = byte.chr
            @current_font_name << char unless char == ';'
          end

          def handle_color_table_plain_byte(byte)
            parse_color_entry if byte.chr == ';'
          end

          def handle_info_plain_byte(byte)
            @info_text << byte.chr
          end

          def append_char(str)
            @current_text << str
          end

          def valid_unicode_codepoint?(codepoint)
            return false unless codepoint.is_a?(Integer)
            return false unless codepoint.between?(0, 0x10FFFF)

            !(0xD800..0xDFFF).cover?(codepoint)
          end

          def skip_unicode_fallback_bytes
            skip_count = @uc_skip
            while skip_count.positive? && @pos < @len
              byte = @rtf.getbyte(@pos)
              break if byte.nil?
              break if self.class::BRACE_BYTES.include?(byte)

              @pos += byte == 92 && hex_escape_start?(@pos) ? 4 : 1
              skip_count -= 1
            end
          end

          def hex_escape_start?(index)
            index + 1 < @len && @rtf.getbyte(index + 1) == 39
          end

          def append_fallback_byte(byte)
            fallback = byte.to_i.chr(Encoding::BINARY).encode(
              'UTF-8',
              invalid: :replace,
              undef: :replace,
              replace: ''
            )
            @current_text << fallback unless fallback.empty?
          rescue ArgumentError, Encoding::CompatibilityError,
                 Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            @current_text << "\uFFFD"
          end
        end
      end
    end
  end
end
