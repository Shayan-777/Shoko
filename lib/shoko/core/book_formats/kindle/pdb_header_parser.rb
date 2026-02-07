# frozen_string_literal: true

module Shoko
  module Core::BookFormats::Kindle
    # Parses the PDB (Palm Database) container header and record offset table
    # from Mobipocket/Kindle binary files (.mobi, .azw, .azw3).
    #
    # PDB header layout (78 bytes, all multi-byte values big-endian):
    #   Offset  Size  Field
    #   0       32    Database name (null-terminated, padded)
    #   32      2     Attributes
    #   34      2     Version
    #   36      4     Creation date (seconds since 1904-01-01)
    #   40      4     Modification date
    #   44      4     Last backup date
    #   48      4     Modification number
    #   52      4     AppInfo ID
    #   56      4     SortInfo ID
    #   60      4     Type (e.g. "BOOK")
    #   64      4     Creator (e.g. "MOBI")
    #   68      4     UniqueIDSeed
    #   72      4     NextRecordListID
    #   76      2     Number of records
    #
    # Record offset table (8 bytes per entry):
    #   Offset  Size  Field
    #   0       4     Record data offset (absolute file position)
    #   4       1     Attributes
    #   5       3     Unique ID (24-bit)
    class PdbHeaderParser
      PDB_HEADER_SIZE = 78
      RECORD_ENTRY_SIZE = 8

      attr_reader :name, :type, :creator, :num_records, :record_offsets

      # @param data [String] raw binary file data (entire file contents)
      def initialize(data)
        @data = data.b
        parse_header
        parse_record_table
      end

      # Extract the raw bytes for a specific record.
      #
      # @param index [Integer] zero-based record index
      # @return [String] raw binary record data
      def record_data(index)
        raise ArgumentError, "Record index #{index} out of range (0..#{@num_records - 1})" unless valid_index?(index)

        start_offset = @record_offsets[index]
        end_offset = if index < @num_records - 1
                       @record_offsets[index + 1]
                     else
                       @data.bytesize
                     end

        @data.byteslice(start_offset, end_offset - start_offset)
      end

      # @return [Integer] size in bytes of record at given index
      def record_size(index)
        raise ArgumentError, "Record index #{index} out of range" unless valid_index?(index)

        start_offset = @record_offsets[index]
        end_offset = index < @num_records - 1 ? @record_offsets[index + 1] : @data.bytesize
        end_offset - start_offset
      end

      private

      def parse_header
        raise Shoko::BookParseError.new('File too small for PDB header', '') if @data.bytesize < PDB_HEADER_SIZE

        @name = @data.byteslice(0, 32).delete("\x00").strip
        @type = @data.byteslice(60, 4)
        @creator = @data.byteslice(64, 4)
        @num_records = @data.byteslice(76, 2).unpack1('n')
      end

      def parse_record_table
        table_size = @num_records * RECORD_ENTRY_SIZE
        required = PDB_HEADER_SIZE + table_size
        if @data.bytesize < required
          raise Shoko::BookParseError.new('File too small for PDB record table', '')
        end

        @record_offsets = Array.new(@num_records)
        @num_records.times do |i|
          entry_offset = PDB_HEADER_SIZE + (i * RECORD_ENTRY_SIZE)
          @record_offsets[i] = @data.byteslice(entry_offset, 4).unpack1('N')
        end
      end

      def valid_index?(index)
        index >= 0 && index < @num_records
      end
    end
  end
end
