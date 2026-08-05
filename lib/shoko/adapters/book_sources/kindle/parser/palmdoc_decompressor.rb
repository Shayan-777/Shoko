# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Adapters
    module BookSources
      module Kindle
        # Implements PalmDOC (LZ77 variant) decompression for Mobipocket text records.
        #
        # Byte-value dispatch:
        #   0x00       → output literal NUL byte
        #   0x01-0x08  → copy next N bytes literally (N = byte value)
        #   0x09-0x7F  → output literal byte
        #   0x80-0xBF  → LZ77 back-reference (2-byte pair):
        #                 bits: [0 DDDDDDD DDDLLLLL] where D=distance, L=length-3
        #                 distance = high 11 bits (shift right 3, mask 0x7FF)
        #                 length   = low 3 bits + 3 (range 3..10)
        #   0xC0-0xFF  → space + (byte XOR 0x80)
        #
        # Each record decompresses independently (no cross-record state).
        module PalmdocDecompressor
          class << self
            # Decompress a single PalmDOC-compressed record.
            #
            # @param data [String] compressed binary data for one record
            # @return [String] decompressed binary output
            def decompress(data, max_output_bytes: nil)
              input = data.b
              output = +''
              output.force_encoding(Encoding::BINARY)
              pos = 0
              context = { input: input, length: input.bytesize, max_output_bytes: max_output_bytes }

              while pos < context[:length]
                byte = input.getbyte(pos)
                pos = process_compressed_byte(context, output, byte, pos + 1)
                enforce_output_limit!(output, context[:max_output_bytes])
              end

              output
            end

            # Remove trailing data entries from a text record before decompression.
            #
            # MOBI files with extra_data_flags set append trailing bytes to each
            # text record. These must be stripped before decompression.
            #
            # Algorithm per KindleUnpack reference:
            #   1. Strip (extra_data_flags >> 1) trailing entries (each has a
            #      backward variable-length size using 0x80 as stop bit)
            #   2. If bit 0 set: strip multibyte overlap (last byte & 0x03 + 1)
            #
            # @param record_data [String] raw record bytes
            # @param extra_data_flags [Integer] uint16 from MOBI header offset 0xF2
            # @return [String] record data with trailing entries removed
            def strip_trailing_data(record_data, extra_data_flags)
              data = record_data.b
              return data if extra_data_flags.zero?

              strip_multibyte_overlap(strip_extra_trailing_entries(data, extra_data_flags), extra_data_flags)
            end

            private

            def process_compressed_byte(context, output, byte, pos)
              return append_literal_null(output, pos) if byte.zero?
              return append_literal_run(context, output, byte, pos) if byte <= 0x08
              return append_literal_byte(output, byte, pos) if byte <= 0x7F
              return append_back_reference(context, output, byte, pos) if byte <= 0xBF

              append_space_encoded_byte(output, byte, pos)
            end

            def append_literal_null(output, pos)
              output << "\x00"
              pos
            end

            def append_literal_run(context, output, count, pos)
              count = context[:length] - pos if pos + count > context[:length]
              output << context[:input].byteslice(pos, count)
              pos + count
            end

            def append_literal_byte(output, byte, pos)
              output << byte.chr(Encoding::BINARY)
              pos
            end

            def append_back_reference(context, output, byte, pos)
              return context[:length] if pos >= context[:length]

              next_byte = context[:input].getbyte(pos)
              copy_back_reference(output, byte, next_byte)
              pos + 1
            end

            def append_space_encoded_byte(output, byte, pos)
              output << ' '
              output << (byte ^ 0x80).chr(Encoding::BINARY)
              pos
            end

            def copy_back_reference(output, byte, next_byte)
              pair = ((byte << 8) | next_byte)
              distance = (pair >> 3) & 0x7FF
              length = (pair & 0x07) + 3
              return unless distance.positive? && distance <= output.bytesize

              start = output.bytesize - distance
              length.times do |index|
                output << output.getbyte(start + index).chr(Encoding::BINARY)
              end
            end

            def enforce_output_limit!(output, max_output_bytes)
              return unless max_output_bytes && output.bytesize > max_output_bytes

              raise Shoko::BookParseError.new(
                "PalmDOC record exceeds #{max_output_bytes} decompressed bytes",
                ''
              )
            end

            def strip_extra_trailing_entries(data, extra_data_flags)
              trailing_count = extra_data_flags >> 1
              trailing_count.times do
                break if data.bytesize < 4

                size = trailing_entry_size(data)
                break if size <= 0 || size > data.bytesize

                data = data.byteslice(0, data.bytesize - size)
              end
              data
            end

            def strip_multibyte_overlap(data, extra_data_flags)
              return data unless extra_data_flags.anybits?(1) && !data.empty?

              overlap = data.getbyte(data.bytesize - 1) & 0x03
              trim = overlap + 1
              trim <= data.bytesize ? data.byteslice(0, data.bytesize - trim) : data
            end

            # Decode a variable-length backward size from the end of the record.
            # Reads bytes from the end; the high bit (0x80) is a stop flag
            # (set = last byte of the encoded size).
            def trailing_entry_size(data)
              return 0 if data.empty?

              size = 0
              shift = 0
              end_bytes = [4, data.bytesize].min

              (1..end_bytes).each do |i|
                byte = data.getbyte(data.bytesize - i)
                size |= ((byte & 0x7F) << shift)
                shift += 7
                return size if byte.anybits?(0x80)
              end

              size
            end
          end
        end
      end
    end
  end
end
