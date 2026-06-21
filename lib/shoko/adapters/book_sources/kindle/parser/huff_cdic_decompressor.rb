# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Adapters
    module BookSources
      module Kindle
        # Decompresses MOBI HUFF/CDIC (compression type 17480) text records —
        # the scheme used by many newer Amazon-sourced .azw3 (and older
        # Mobipocket) files, which PalmDOC-only readers reject.
        #
        # The format is a Huffman code over a phrase dictionary: one HUFF record
        # carries the code tables (a 256-entry cache table + a 32-length base
        # table), one or more CDIC records carry the dictionary of phrases (each
        # either a literal byte run or itself a compressed bitstream), and every
        # text record is a stream of variable-length codes that resolve to
        # dictionary phrases.
        #
        # Ported from the reference decoder in Calibre/KindleUnpack. The decoder
        # is stateful by design: build it once from the HUFF + CDIC records, then
        # call #decompress for each text record. Non-terminal phrases are decoded
        # lazily and cached back into the dictionary across calls, exactly as the
        # reference does, so repeated phrases cost nothing after first use.
        class HuffCdicDecompressor
          HUFF_MAGIC = "HUFF\x00\x00\x00\x18".b
          CDIC_MAGIC = "CDIC\x00\x00\x00\x10".b
          U32_MASK = 0xFFFF_FFFF
          MAX_CODE_LENGTH = 32

          # MSB-first reader over a 64-bit window that slides four bytes at a
          # time. Eight trailing zero bytes let the final codes read past the
          # real data without bounds checks; #advance reports when the record's
          # bits are spent. One reader per decode call keeps the recursion in
          # HuffCdicDecompressor#unpack self-contained.
          class BitReader
            def initialize(data)
              @buffer = data + ("\x00".b * 8)
              @bits_left = data.bytesize * 8
              @position = 0
              @available = 32
              @window = read_window
            end

            def current_code
              if @available <= 0
                @position += 4
                @window = read_window
                @available += 32
              end
              (@window >> @available) & U32_MASK
            end

            # Consumes +codelen+ bits of the record.
            def advance(codelen)
              @available -= codelen
              @bits_left -= codelen
            end

            # True once the record's real bits are exhausted (the final code ran
            # into the zero padding).
            def spent?
              @bits_left.negative?
            end

            private

            def read_window
              chunk = @buffer.byteslice(@position, 8).to_s
              chunk = chunk.ljust(8, "\x00".b) if chunk.bytesize < 8
              chunk.unpack1('Q>')
            end
          end

          # @param huff_record [String] raw bytes of the HUFF record
          # @param cdic_records [Array<String>] raw bytes of the CDIC records
          def initialize(huff_record, cdic_records)
            load_huff(huff_record.to_s.b)
            @dictionary = []
            Array(cdic_records).each { |cdic| load_cdic(cdic.to_s.b) }
          end

          # Decompress one text record (trailing extra-data already stripped).
          #
          # @param data [String] compressed binary data for one record
          # @return [String] decompressed binary output
          def decompress(data)
            unpack(data.to_s.b)
          end

          private

          def load_huff(huff)
            raise malformed('invalid HUFF record header') unless huff.byteslice(0, 8) == HUFF_MAGIC

            cache_offset, base_offset = huff.byteslice(8, 8).to_s.unpack('N2')
            @dict1 = decode_cache_table(huff, cache_offset)
            build_base_tables(decode_base_table(huff, base_offset))
          end

          def decode_cache_table(huff, offset)
            # `unpack('N256')` pads a short slice with nils rather than failing,
            # so validate the raw byte length before decoding.
            slice = huff.byteslice(offset.to_i, 256 * 4)
            raise malformed('truncated HUFF cache table') unless slice&.bytesize == 256 * 4

            slice.unpack('N256').map { |value| decode_cache_entry(value) }
          end

          # Each cache entry packs the code length, a "terminal" flag, and the
          # base code: codelen low 5 bits, term at 0x80, max code in the high
          # bits. The stored max code is widened to a left-aligned 32-bit bound.
          def decode_cache_entry(value)
            codelen = value & 0x1F
            term = value & 0x80
            maxcode = value >> 8
            raise malformed('zero-length HUFF code') if codelen.zero?

            [codelen, term, (((maxcode + 1) << (MAX_CODE_LENGTH - codelen)) - 1)]
          end

          def decode_base_table(huff, offset)
            slice = huff.byteslice(offset.to_i, 64 * 4)
            raise malformed('truncated HUFF base table') unless slice&.bytesize == 64 * 4

            slice.unpack('N64')
          end

          # The base table is 32 (min, max) pairs indexed by code length. A
          # leading zero entry makes both arrays directly indexable by the code
          # length (1..32) the cache table / resolution loop produce.
          def build_base_tables(base_words)
            mins = [0] + base_words.each_slice(2).map(&:first)
            maxs = [0] + base_words.each_slice(2).map(&:last)
            @mincode = mins.each_with_index.map { |value, codelen| value << (MAX_CODE_LENGTH - codelen) }
            @maxcode = maxs.each_with_index.map { |value, codelen| ((value + 1) << (MAX_CODE_LENGTH - codelen)) - 1 }
          end

          def load_cdic(cdic)
            raise malformed('invalid CDIC record header') unless cdic.byteslice(0, 8) == CDIC_MAGIC

            phrase_count, index_bits = cdic.byteslice(8, 8).to_s.unpack('N2')
            remaining = phrase_count.to_i - @dictionary.length
            count = [1 << index_bits.to_i, remaining].min
            return if count <= 0

            append_cdic_phrases(cdic, count)
          end

          def append_cdic_phrases(cdic, count)
            slice = cdic.byteslice(16, count * 2)
            raise malformed('truncated CDIC offset index') unless slice&.bytesize == count * 2

            slice.unpack("n#{count}").each { |offset| @dictionary << cdic_phrase(cdic, offset) }
          end

          def cdic_phrase(cdic, offset)
            length_word = cdic.byteslice(16 + offset, 2).to_s.unpack1('n')
            raise malformed('truncated CDIC phrase length') if length_word.nil?

            slice = cdic.byteslice(18 + offset, length_word & 0x7FFF).to_s
            [slice, length_word & 0x8000]
          end

          # Decodes one record by walking codes MSB-first through the bit
          # window, resolving each code to its length/range and then to a
          # dictionary phrase. Recursion-safe: each call owns its own reader.
          def unpack(data)
            reader = BitReader.new(data)
            out = []
            loop do
              code = reader.current_code
              codelen, maxcode = code_length_and_max(code)
              reader.advance(codelen)
              break if reader.spent?

              out << dictionary_phrase((maxcode - code) >> (MAX_CODE_LENGTH - codelen))
            end
            out.join
          end

          def code_length_and_max(code)
            codelen, term, maxcode = @dict1[code >> 24]
            return [codelen, maxcode] unless term.zero?

            # Non-terminal cache hit: walk to the real code length for this code.
            codelen += 1 while codelen <= MAX_CODE_LENGTH && code < @mincode[codelen]
            raise malformed('HUFF code length overflow') if codelen > MAX_CODE_LENGTH

            [codelen, @maxcode[codelen]]
          end

          def dictionary_phrase(index)
            entry = @dictionary[index]
            raise malformed('CDIC dictionary index out of range') if entry.nil?

            slice, terminal = entry
            return slice unless terminal.zero?

            # A clear terminal flag means the phrase is itself a compressed
            # bitstream; decode it once and cache the result (marked terminal),
            # nilling the slot first so a self-referential phrase can't recurse
            # forever on malformed input.
            @dictionary[index] = nil
            decoded = unpack(slice)
            @dictionary[index] = [decoded, 0x8000]
            decoded
          end

          def malformed(reason)
            Shoko::BookParseError.new("HUFF/CDIC decompression failed: #{reason}", '')
          end
        end
      end
    end
  end
end
