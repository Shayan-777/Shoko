# frozen_string_literal: true

require_relative 'decoder_scanner'
require_relative 'decoder_utils'
require_relative 'esc_sequence_parser'
require_relative 'utf8_decoder'

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalInput
          # Stateful tokenizer for raw terminal input.
          #
          # Converts a stream of bytes into:
          # - Full CSI sequences (e.g. "\e[1;5D", mouse "\e[<...M")
          # - Full SS3 sequences (e.g. "\eOA")
          # - UTF-8 characters (including multibyte)
          # - A lone ESC ("\e") after a small timeout (to disambiguate from escapes)
          class Decoder
            DEFAULT_ESC_TIMEOUT = 0.05
            DEFAULT_SEQUENCE_TIMEOUT = 0.5

            ESC = 0x1B
            CSI_8BIT = 0x9B

            def initialize(esc_timeout: DEFAULT_ESC_TIMEOUT, sequence_timeout: DEFAULT_SEQUENCE_TIMEOUT)
              @esc_timeout = DecoderUtils.normalize_timeout(esc_timeout, DEFAULT_ESC_TIMEOUT)
              @sequence_timeout = DecoderUtils.normalize_timeout(sequence_timeout, DEFAULT_SEQUENCE_TIMEOUT)
              @buffer = +''.b
              @pending_started_at = nil
            end

            def feed(bytes)
              chunk = bytes.to_s
              return if chunk.empty?

              chunk = String(chunk).dup.force_encoding(Encoding::BINARY)
              @buffer << chunk
            end

            # Returns the next decoded token, or nil if not enough bytes are available.
            def next_token(now: DecoderUtils.monotonic_now)
              return nil if @buffer.empty?

              token = parse_token
              return token if token

              now < pending_deadline(now) ? nil : degrade_pending_token
            end

            # When a partial token is buffered, returns seconds to wait before a token
            # should be emitted even if no further bytes arrive.
            def pending_timeout(now: DecoderUtils.monotonic_now)
              return nil if @buffer.empty?
              return nil unless @pending_started_at

              remaining = pending_deadline(now) - now
              remaining.positive? ? remaining : 0
            end

            private

            def consume_and_clear(byte_count)
              consume_bytes(byte_count)
              @pending_started_at = nil
            end

            def pending_deadline(now)
              started = @pending_started_at || now
              @pending_started_at = started
              if @buffer.bytesize == 1 && @buffer.getbyte(0) == ESC
                started + @esc_timeout
              else
                started + @sequence_timeout
              end
            end

            def parse_token
              first = @buffer.getbyte(0)
              case first
              when ESC
                return nil if @buffer.bytesize < 2

                EscSequenceParser.new(@buffer, self).parse
              when CSI_8BIT
                parse_csi_sequence(prefix_bytes: 1, output_prefix: "\e[")
              else
                parse_decoded_character(0)
              end
            end

            def parse_ss3_sequence
              return nil if @buffer.bytesize < 3

              token = @buffer.byteslice(0, 3)
              consume_and_clear(3)
              token.force_encoding(Encoding::UTF_8)
            end

            def parse_csi_sequence(prefix_bytes:, output_prefix:)
              if x10_mouse_prefix?(prefix_bytes)
                min_length = prefix_bytes == 1 ? 5 : 6
                return nil if @buffer.bytesize < min_length

                return parse_x10_mouse_sequence(prefix_bytes)
              end

              return nil unless (final_index = DecoderScanner.new(@buffer).csi_final_index(prefix_bytes))

              end_index = final_index + 1
              raw = @buffer.byteslice(0, end_index)
              consume_and_clear(end_index)
              DecoderUtils.format_csi_output(raw, prefix_bytes, output_prefix)
            end

            def parse_string_sequence(end_index)
              return nil unless end_index

              raw = @buffer.byteslice(0, end_index)
              consume_and_clear(end_index)
              raw.force_encoding(Encoding::UTF_8)
            end

            def parse_decoded_character(offset, prefix: nil)
              return nil unless (decoded = Utf8Decoder.new(@buffer).decode_at(offset))

              char, consumed = decoded
              consume_and_clear(offset + consumed)
              prefix ? "#{prefix}#{char}" : char
            end

            def x10_mouse_prefix?(prefix_bytes)
              case prefix_bytes
              when 2
                return false unless @buffer.bytesize >= 3

                @buffer.getbyte(0) == ESC && @buffer.getbyte(1) == 0x5B && @buffer.getbyte(2) == 0x4D
              when 1
                return false unless @buffer.bytesize >= 2

                @buffer.getbyte(0) == CSI_8BIT && @buffer.getbyte(1) == 0x4D
              else
                false
              end
            end

            def parse_x10_mouse_sequence(prefix_bytes)
              length = prefix_bytes + 1 + 3
              raw = @buffer.byteslice(0, length)
              consume_and_clear(length)
              if prefix_bytes == 1
                coords = raw.byteslice(2, 3) || ''.b
                return "\e[M".b + coords
              end

              raw.force_encoding(Encoding::BINARY)
            end

            def degrade_pending_token
              lead_byte = @buffer.getbyte(0)
              consume_and_clear(1)

              { ESC => "\e", CSI_8BIT => "\e[" }.fetch(lead_byte, "\uFFFD")
            end

            def consume_bytes(byte_count)
              count = byte_count.to_i
              return if count <= 0

              @buffer.slice!(0, count)
            end
          end
        end
      end
    end
  end
end
