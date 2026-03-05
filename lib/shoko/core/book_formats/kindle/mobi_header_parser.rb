# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Kindle
        # Parses the PalmDOC header and MOBI header from record 0 of a
        # Mobipocket/Kindle file.
        #
        # Record 0 layout:
        #   PalmDOC header (bytes 0-15)
        #   MOBI header    (bytes 16+, variable length 232-264 bytes)
        #   EXTH header    (optional, follows MOBI header)
        #   Full book name (at full_name_offset within record 0)
        class MobiHeaderParser
          MOBI_MAGIC = 'MOBI'

          # Compression types
          COMPRESSION_NONE    = 1
          COMPRESSION_PALMDOC = 2
          COMPRESSION_HUFFCDIC = 17_480

          # Encryption types
          ENCRYPTION_NONE    = 0
          ENCRYPTION_OLD     = 1
          ENCRYPTION_CURRENT = 2

          # Text encodings
          ENCODING_CP1252 = 1252
          ENCODING_UTF8   = 65_001

          attr_reader :record0

          # PalmDOC header fields
          attr_reader :compression_type, :text_length, :text_record_count,
                      :record_size, :encryption_type

          # MOBI header fields
          attr_reader :mobi_header_length, :mobi_type, :text_encoding,
                      :file_version, :first_non_book_record, :full_name_offset,
                      :full_name_length, :first_image_record, :exth_flags,
                      :first_content_record, :last_content_record, :extra_data_flags

          # @param record0_data [String] raw binary data of PDB record 0
          def initialize(record0_data)
            @record0 = record0_data.b
            parse_palmdoc_header
            parse_mobi_header
          end

          # @return [Boolean] true if EXTH header is present
          def has_exth?
            @exth_flags.anybits?(0x40)
          end

          # @return [Boolean] true if file uses KF8 (version 8) format
          def kf8?
            @file_version >= 8
          end

          # @return [String] text encoding name suitable for Ruby's Encoding
          def encoding_name
            case @text_encoding
            when ENCODING_UTF8 then 'UTF-8'
            when ENCODING_CP1252 then 'Windows-1252'
            else 'UTF-8'
            end
          end

          # @return [Boolean] true if content uses PalmDOC compression
          def palmdoc_compressed?
            @compression_type == COMPRESSION_PALMDOC
          end

          # @return [Boolean] true if content is uncompressed
          def uncompressed?
            @compression_type == COMPRESSION_NONE
          end

          # @return [Boolean] true if DRM is applied
          def drm?
            @encryption_type != ENCRYPTION_NONE
          end

          # @return [String] full book name extracted from record 0
          def full_name
            # Try the explicit offset first
            name = read_name_at_offset
            return name unless name.empty?

            # Fallback: name stored after EXTH header (common in Kindle files)
            name = read_name_after_exth
            return name unless name.empty?

            ''
          end

          # @return [Integer] byte offset where EXTH header starts in record 0
          def exth_offset
            16 + @mobi_header_length
          end

          # @return [Integer] number of extra trailing data entries per text record
          #   (equals extra_data_flags >> 1)
          def trailing_entry_count
            @extra_data_flags >> 1
          end

          # @return [Boolean] true if records have multibyte overlap trailing bytes
          def multibyte_overlap?
            @extra_data_flags.anybits?(1)
          end

          private

          def parse_palmdoc_header
            raise Shoko::BookParseError.new('Record 0 too small', '') if @record0.bytesize < 16

            @compression_type  = uint16(0)
            # bytes 2-3 unused
            @text_length       = uint32(4)
            @text_record_count = uint16(8)
            @record_size       = uint16(10)
            @encryption_type   = uint16(12)
          end

          def parse_mobi_header
            raise Shoko::BookParseError.new('Record 0 too small for MOBI header', '') if @record0.bytesize < 24

            magic = @record0.byteslice(16, 4)
            unless magic == MOBI_MAGIC
              raise Shoko::BookParseError.new("Invalid MOBI header magic: #{magic.inspect}", '')
            end

            @mobi_header_length   = uint32(20)
            @mobi_type            = uint32(24)
            @text_encoding        = uint32(28)
            @file_version         = uint32(36)
            @first_non_book_record = uint32(48)
            @full_name_offset     = uint32(52)
            @full_name_length     = uint32(56)
            @first_image_record   = uint32(76)

            # EXTH flags at offset 128 (relative to record 0 start)
            @exth_flags = @record0.bytesize > 131 ? uint32(128) : 0

            # First/last content record indices (MOBI 6+ fields)
            if @record0.bytesize > 115
              @first_content_record = uint16(192)
              @last_content_record = uint16(194)
            else
              @first_content_record = 1
              @last_content_record = @text_record_count
            end

            # Extra data flags — location varies by header length
            @extra_data_flags = read_extra_data_flags
          end

          def read_name_at_offset
            return '' if @full_name_offset >= 0xFFFFFFFF || @full_name_length >= 0xFFFFFFFF
            return '' if @full_name_offset.zero? || @full_name_length.zero?
            return '' if @full_name_offset + @full_name_length > @record0.bytesize

            raw = @record0.byteslice(@full_name_offset, @full_name_length)
            raw.force_encoding(encoding_name)
            raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
            raise Shoko::BookParseError.new("Unable to decode MOBI title at explicit offset: #{e.message}", '')
          end

          def read_name_after_exth
            return '' unless has_exth?

            exth_start = exth_offset
            return '' if exth_start + 8 > @record0.bytesize
            return '' unless @record0.byteslice(exth_start, 4) == 'EXTH'

            exth_len = @record0.byteslice(exth_start + 4, 4).unpack1('N')
            name_start = exth_start + exth_len
            # Align to 4-byte boundary
            name_start += (4 - (name_start % 4)) % 4
            return '' if name_start >= @record0.bytesize

            # Read a chunk after EXTH and find the name within it
            max_len = [@record0.bytesize - name_start, 500].min
            raw = @record0.byteslice(name_start, max_len)

            # Skip leading NUL bytes (some formats pad before the name)
            raw = raw.sub(/\A\x00+/, '')
            return '' if raw.empty?

            # Trim at first NUL
            nul_pos = raw.index("\x00")
            raw = raw.byteslice(0, nul_pos) if nul_pos

            raw.force_encoding(encoding_name)
            raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
            raise Shoko::BookParseError.new("Unable to decode MOBI title after EXTH: #{e.message}", '')
          end

          def read_extra_data_flags
            # Extra data flags is a uint16 at fixed offset 0xF2 (242) in record 0,
            # only present when MOBI header length >= 0xE4 (228 bytes).
            # Per KindleUnpack reference implementation.
            return 0 if @mobi_header_length < 228
            return 0 if @record0.bytesize < 244

            uint16(242)
          end

          def uint16(offset)
            @record0.byteslice(offset, 2).unpack1('n')
          end

          def uint32(offset)
            @record0.byteslice(offset, 4).unpack1('N')
          end
        end
      end
    end
  end
end
