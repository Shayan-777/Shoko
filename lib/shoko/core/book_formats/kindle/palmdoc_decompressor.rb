# frozen_string_literal: true

module Shoko
  module Core::BookFormats::Kindle
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
        def decompress(data)
          input = data.b
          output = +''
          output.force_encoding(Encoding::BINARY)
          pos = 0
          len = input.bytesize

          while pos < len
            byte = input.getbyte(pos)
            pos += 1

            if byte == 0x00
              # Literal NUL
              output << "\x00"
            elsif byte <= 0x08
              # Copy next N bytes literally
              count = byte
              count = len - pos if pos + count > len
              output << input.byteslice(pos, count)
              pos += count
            elsif byte <= 0x7F
              # Literal byte
              output << byte.chr(Encoding::BINARY)
            elsif byte <= 0xBF
              # LZ77 back-reference: need one more byte
              break if pos >= len

              next_byte = input.getbyte(pos)
              pos += 1

              # Combine into 16-bit value (big-endian interpretation)
              pair = ((byte << 8) | next_byte)
              distance = (pair >> 3) & 0x7FF
              length = (pair & 0x07) + 3

              # Copy from output buffer (may overlap — byte at a time)
              if distance > 0 && distance <= output.bytesize
                start = output.bytesize - distance
                length.times do |i|
                  output << output.getbyte(start + i).chr(Encoding::BINARY)
                end
              end
            else
              # 0xC0-0xFF: space + decoded character
              output << ' '
              output << (byte ^ 0x80).chr(Encoding::BINARY)
            end
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

          # Strip extra trailing entries (count = flags >> 1)
          trailing_count = extra_data_flags >> 1
          trailing_count.times do
            break if data.bytesize < 4

            size = trailing_entry_size(data)
            break if size <= 0 || size > data.bytesize

            data = data.byteslice(0, data.bytesize - size)
          end

          # Bit 0 (multibyte overlap): last byte's low 2 bits = overlap byte count
          if (extra_data_flags & 1) != 0 && !data.empty?
            overlap = data.getbyte(data.bytesize - 1) & 0x03
            trim = overlap + 1 # +1 for the overlap-count byte itself
            data = data.byteslice(0, data.bytesize - trim) if trim <= data.bytesize
          end

          data
        end

        private

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
            return size if (byte & 0x80) != 0
          end

          size
        end
      end
    end
  end
end
