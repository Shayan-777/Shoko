# frozen_string_literal: true

require_relative 'utf8_validator'

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalInput
          # UTF-8 decoder for buffered terminal input.
          class Utf8Decoder
            def initialize(buffer)
              @buffer = buffer
            end

            def decode_at(offset)
              lead_byte = @buffer.getbyte(offset)
              return nil unless lead_byte
              return [@buffer.byteslice(offset, 1).force_encoding(Encoding::UTF_8), 1] if lead_byte < 0x80

              decode_multibyte_at(offset, lead_byte)
            end

            private

            def decode_multibyte_at(offset, lead_byte)
              byte_length =
                (2 if lead_byte.between?(0xC2, 0xDF)) ||
                (3 if lead_byte.between?(0xE0, 0xEF)) ||
                (4 if lead_byte.between?(0xF0, 0xF4))
              return invalid_utf8_token unless byte_length
              return nil if @buffer.bytesize < offset + byte_length

              decode_multibyte(offset, byte_length)
            end

            def decode_multibyte(offset, byte_length)
              bytes = @buffer.byteslice(offset, byte_length)
              Utf8Validator.new(bytes).valid? ? utf8_token(bytes, byte_length) : invalid_utf8_token
            end

            def utf8_token(bytes, byte_length)
              char = bytes.dup.force_encoding(Encoding::UTF_8)
              char.valid_encoding? ? [char, byte_length] : invalid_utf8_token
            end

            def invalid_utf8_token
              ["\uFFFD", 1]
            end
          end
        end
      end
    end
  end
end
