# frozen_string_literal: true

require_relative 'central_directory_header_parser'
require_relative 'central_directory_variable_fields'
require_relative 'entry_factory'
require_relative 'entry_reader'
require_relative 'eocd_parser'
require_relative 'error'
require_relative 'file_state'
require_relative 'name_normalizer'
require_relative 'signatures'
require_relative 'size_limits'
require_relative 'sizes'

module Shoko
  module Zip
    # Read-only ZIP archive reader with explicit size safeguards.
    class File
      def self.open(path, **)
        zip_file = new(path, **)
        return zip_file unless block_given?

        begin
          yield zip_file
        ensure
          close_safely(zip_file)
        end
      end

      # Closing an IO raises IOError/SystemCallError, never a Shoko error;
      # the old `rescue Shoko::Error` could not catch what close actually
      # raises, so its "ignore close errors" promise was false.
      def self.close_safely(zip_file)
        zip_file.close
      rescue IOError, SystemCallError
        # ignore close errors
      end

      def initialize(path,
                     max_entry_uncompressed_bytes: nil,
                     max_entry_compressed_bytes: nil,
                     max_total_uncompressed_bytes: nil)
        initialized = false
        limits = SizeLimits.new(
          max_entry_uncompressed: max_entry_uncompressed_bytes,
          max_entry_compressed: max_entry_compressed_bytes,
          max_total_uncompressed: max_total_uncompressed_bytes
        )
        @state = FileState.new(path, limits)
        @io = @state.io
        @entries = @state.entries
        build_index!
        initialized = true
      ensure
        cleanup_failed_initialization unless initialized
      end

      def close
        @state.close
      end

      def closed?
        @state.closed?
      end

      def find_entry(path)
        normalized_path = NameNormalizer.normalize(path)
        @entries[normalized_path]
      end

      def entries
        @entries.values
      end

      def read(path)
        entry = find_entry_or_raise(path)
        validate_entry_readable(entry)
        limits = @state.limits
        limits.enforce_entry_limits(entry, requested_name: path)
        EntryReader.new(@state.io, limits).read_entry(entry)
      end

      private

      def build_index!
        cd_offset, cd_size = locate_central_directory
        read_central_directory_entries(cd_offset, cd_size)
      end

      def read_central_directory_entries(cd_offset, cd_size)
        @io.seek(cd_offset, ::IO::SEEK_SET)
        stop_position = cd_offset + cd_size

        while @io.pos < stop_position
          entry = read_central_directory_entry
          @entries[entry.name] = entry
        end
      end

      def read_central_directory_entry
        verify_signature(Signatures::CENTRAL_DIR, 'invalid central directory header signature')
        fixed_header = read_exact(42, error_message: 'truncated central directory header')
        build_entry_from_header(fixed_header)
      end

      def build_entry_from_header(fixed_header)
        header_data = CentralDirectoryHeaderParser.new(fixed_header).parse
        variable_fields = CentralDirectoryVariableFields.new(@io, header_data)
        entry_name = variable_fields.read_and_skip
        EntryFactory.create_from_header(entry_name, header_data)
      end

      def locate_central_directory
        file_size = @io.stat.size
        tail_data = read_file_tail(file_size)
        eocd_index = find_eocd_signature(tail_data)
        EOCDParser.parse(tail_data, eocd_index)
      end

      def read_file_tail(file_size)
        scan_size = [file_size, Sizes::MAX_EOCD_SCAN].min
        @io.seek(file_size - scan_size, ::IO::SEEK_SET)
        tail_data = @io.read(scan_size)
        raise Error, 'unable to read file tail' unless tail_data

        tail_data
      end

      def find_eocd_signature(tail_data)
        eocd_index = tail_data.rindex(Signatures::EOCD)
        raise Error, 'end of central directory not found' unless eocd_index

        eocd_index
      end

      def cleanup_failed_initialization
        @state&.close
      rescue IOError, SystemCallError
        # best-effort state cleanup on constructor failure
      end

      def find_entry_or_raise(path)
        entry = find_entry(path)
        raise Error, "entry not found: #{path}" unless entry

        entry
      end

      def validate_entry_readable(entry)
        entry_name = entry.name
        raise Error, "cannot read directory entry: #{entry_name}" if entry_name.end_with?('/')

        gp_flags = entry.gp_flags.to_i
        raise Error, "unsupported encrypted entry: #{entry_name}" if gp_flags.anybits?(0x1)
      end

      def verify_signature(expected_signature, error_message)
        signature_bytes = @io.read(expected_signature.bytesize)
        raise Error, error_message unless signature_bytes == expected_signature
      end

      def read_exact(byte_count, error_message:)
        data = @io.read(byte_count)
        return data if data && data.bytesize == byte_count

        raise Error, error_message
      end
    end
  end
end
