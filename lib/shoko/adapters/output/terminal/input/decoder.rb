# frozen_string_literal: true

module Shoko
  module Adapters::Output::Terminal
    class TerminalInput
      # Utility helpers for timeouts and CSI formatting.
      module DecoderUtils
        module_function

        def normalize_timeout(value, default)
          seconds = value.to_f
          seconds.positive? ? seconds : default
        rescue StandardError
          default
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        rescue StandardError
          Time.now.to_f
        end

        def format_csi_output(raw, prefix_bytes, output_prefix)
          return raw.force_encoding(Encoding::UTF_8) unless output_prefix

          remainder = raw.byteslice(prefix_bytes..) || ''.b
          (output_prefix + remainder.force_encoding(Encoding::UTF_8)).freeze
        end
      end

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
        rescue StandardError
          invalid_utf8_token
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

      # Validates UTF-8 byte sequences.
      class Utf8Validator
        def initialize(bytes)
          @bytes = bytes
        end

        def valid?
          case @bytes.bytesize
          when 2
            valid_2_bytes?
          when 3
            valid_3_bytes?
          when 4
            valid_4_bytes?
          else
            false
          end
        end

        private

        def valid_2_bytes?
          byte_at(1).between?(0x80, 0xBF)
        end

        def valid_3_bytes?
          lead_byte = byte_at(0)
          first_continuation = byte_at(1)
          second_continuation = byte_at(2)
          first_continuation.between?(0x80, 0xBF) &&
            second_continuation.between?(0x80, 0xBF) &&
            !(lead_byte == 0xE0 && first_continuation < 0xA0) &&
            !(lead_byte == 0xED && first_continuation > 0x9F)
        end

        def valid_4_bytes?
          lead_byte = byte_at(0)
          first_continuation = byte_at(1)
          second_continuation = byte_at(2)
          third_continuation = byte_at(3)
          first_continuation.between?(0x80, 0xBF) &&
            second_continuation.between?(0x80, 0xBF) &&
            third_continuation.between?(0x80, 0xBF) &&
            !(lead_byte == 0xF0 && first_continuation < 0x90) &&
            !(lead_byte == 0xF4 && first_continuation > 0x8F)
        end

        def byte_at(index)
          @bytes.getbyte(index)
        end
      end

      # Scanning helpers for CSI and string terminators.
      class DecoderScanner
        def initialize(buffer)
          @buffer = buffer
        end

        def csi_final_index(start_offset)
          index = start_offset
          while index < @buffer.bytesize
            return index if @buffer.getbyte(index).between?(0x40, 0x7E)

            index += 1
          end
        end

        def string_terminator_index(start_offset)
          start_offset.upto(@buffer.bytesize - 1) do |index|
            length = string_terminator_length(index)
            return index + length if length
          end
        end

        def osc_terminator_index(start_offset)
          start_offset.upto(@buffer.bytesize - 1) do |index|
            length = osc_terminator_length(index)
            return index + length if length
          end
        end

        private

        def string_terminator_length(index)
          case @buffer.getbyte(index)
          when 0x9C
            1
          when 0x1B
            2 if @buffer.getbyte(index + 1) == 0x5C
          end
        end

        def osc_terminator_length(index)
          case @buffer.getbyte(index)
          when 0x07, 0x9C
            1
          when 0x1B
            2 if @buffer.getbyte(index + 1) == 0x5C
          end
        end
      end

      # Dispatches ESC-prefixed sequences to decoder actions.
      class EscSequenceParser
        HANDLERS = {
          0x1B => :escape,
          0x5B => :csi,
          0x4F => :ss3,
          0x5D => :osc,
          0x50 => :string,
          0x58 => :string,
          0x5E => :string,
          0x5F => :string,
        }.freeze

        ACTIONS = {
          escape: lambda do |_scanner|
            consume_and_clear(1)
            "\e"
          end,
          csi: ->(_scanner) { parse_csi_sequence(prefix_bytes: 2, output_prefix: nil) },
          ss3: ->(_scanner) { parse_ss3_sequence },
          osc: ->(scanner) { parse_string_sequence(scanner.osc_terminator_index(2)) },
          string: ->(scanner) { parse_string_sequence(scanner.string_terminator_index(2)) },
          alt: ->(_scanner) { parse_decoded_character(1, prefix: "\e") },
        }.freeze

        def initialize(buffer, decoder)
          @buffer = buffer
          @decoder = decoder
          @scanner = DecoderScanner.new(buffer)
        end

        def parse
          action = HANDLERS.fetch(@buffer.getbyte(1), :alt)
          @decoder.instance_exec(@scanner, &ACTIONS.fetch(action))
        end
      end

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
        rescue StandardError
          nil
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
        rescue StandardError
          @buffer = +''.b
        end
      end
    end
  end
end
