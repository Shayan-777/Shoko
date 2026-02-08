# frozen_string_literal: true

# Minimal, read-only ZIP reader compatible with the subset of rubyzip API
# used by this project. Supports STORE (0) and DEFLATE (8) entries.
#
# Public API:
#   Zip::File.open(path) { |zip| ... }
#   zip.read(entry_path) -> String (binary)
#   zip.find_entry(entry_path) -> entry or nil
#   zip.close ; zip.closed?
#   Zip::Error raised for malformed/unsupported archives or missing entries

require 'zlib'

# Namespace for ZIP file operations
module Zip
  # Base error class for all ZIP-related errors
  class Error < StandardError; end

  # Metadata for a Central Directory entry.
  Entry = Struct.new(
    :name,
    :compressed_size,
    :uncompressed_size,
    :compression_method,
    :gp_flags,
    :local_header_offset,
    keyword_init: true
  )

  # ZIP file format signature constants
  module Signatures
    EOCD = [0x06054B50].pack('V').freeze # "PK\x05\x06"
    CENTRAL_DIR = [0x02014B50].pack('V').freeze # "PK\x01\x02"
    LOCAL_FILE = [0x04034B50].pack('V').freeze # "PK\x03\x04"
  end

  # ZIP file format size constants
  module Sizes
    MAX_EOCD_SCAN = 66_560 # 64 KiB comment + 2 KiB buffer
    READ_CHUNK = 16 * 1024
  end

  # Default size limit constants
  module Limits
    MAX_ENTRY_COMPRESSED = 64 * 1024 * 1024
    MAX_ENTRY_UNCOMPRESSED = 64 * 1024 * 1024
    MAX_TOTAL_UNCOMPRESSED = 256 * 1024 * 1024
  end

  # Utilities for normalizing entry names
  module NameNormalizer
    module_function

    def normalize(name)
      string_value = ensure_string(name)
      binary_string = string_value.force_encoding(Encoding::BINARY)
      with_forward_slashes = binary_string.tr('\\', '/')
      remove_leading_dot_slash(with_forward_slashes)
    end

    def ensure_string(name)
      name.is_a?(String) ? name.dup : name.to_s
    end

    def remove_leading_dot_slash(path)
      path.sub(%r{^\./}, '')
    end
  end

  # Parser for Central Directory Fixed Header fields
  class CentralDirectoryHeaderParser
    FIELD_INDICES = {
      gp_flags: 2,
      compression_method: 3,
      compressed_size: 7,
      uncompressed_size: 8,
      name_length: 9,
      extra_length: 10,
      comment_length: 11,
      local_header_offset: 15,
    }.freeze

    def self.extract_named_fields(field_values)
      FIELD_INDICES.transform_values { |index| field_values[index] }
    end

    def initialize(header_bytes)
      @header_bytes = header_bytes
    end

    def parse
      field_values = @header_bytes.unpack('v v v v v v V V V v v v v v V V')
      self.class.extract_named_fields(field_values)
    end
  end

  # Parser for End of Central Directory record
  class EOCDParser
    def self.parse(tail_data, eocd_index)
      new(tail_data, eocd_index).parse
    end

    def self.extract_directory_info(eocd_record)
      cd_size = eocd_record.byteslice(12, 4).unpack1('V')
      cd_offset = eocd_record.byteslice(16, 4).unpack1('V')
      [cd_offset, cd_size]
    end

    def initialize(tail_data, eocd_index)
      @tail_data = tail_data
      @eocd_index = eocd_index
    end

    def parse
      eocd_record = extract_eocd_record
      validate_eocd_record(eocd_record)
      self.class.extract_directory_info(eocd_record)
    end

    private

    def extract_eocd_record
      @tail_data.byteslice(@eocd_index, 22)
    end

    def validate_eocd_record(eocd_record)
      raise Error, 'truncated EOCD' unless eocd_record && eocd_record.bytesize == 22
    end
  end

  # Factory for creating Entry objects from Central Directory data
  class EntryFactory
    def self.create_from_header(normalized_name, header_data)
      Entry.new(
        name: normalized_name,
        compressed_size: header_data[:compressed_size],
        uncompressed_size: header_data[:uncompressed_size],
        compression_method: header_data[:compression_method],
        gp_flags: header_data[:gp_flags],
        local_header_offset: header_data[:local_header_offset]
      )
    end
  end

  # Extracts variable-length fields from Central Directory entry
  class CentralDirectoryVariableFields
    def initialize(io, header_data)
      @io = io
      @header_data = header_data
    end

    def read_and_skip
      entry_name = read_entry_name
      skip_extra_and_comment
      entry_name
    end

    private

    def read_entry_name
      name_length = @header_data[:name_length]
      raw_name = @io.read(name_length) || ''
      NameNormalizer.normalize(raw_name)
    end

    def skip_extra_and_comment
      extra_length = @header_data[:extra_length]
      comment_length = @header_data[:comment_length]
      total_skip = extra_length + comment_length
      skip_bytes(total_skip)
    end

    def skip_bytes(byte_count)
      return if byte_count.to_i <= 0

      @io.seek(byte_count, ::IO::SEEK_CUR)
    end
  end

  # Helpers for indexing entries via the Central Directory.
  module IndexBuilder
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
  end

  # Context for entry validation operations
  class ValidationContext
    attr_reader :entry, :requested_name

    def initialize(entry, requested_name)
      @entry = entry
      @requested_name = requested_name
    end

    def compressed_size
      entry.compressed_size.to_i
    end

    def uncompressed_size
      @uncompressed_size ||= entry.uncompressed_size.to_i
    end

    def uncompressed_size_positive?
      uncompressed_size.positive?
    end

    def entry_name
      entry.name
    end

    def exceeds_uncompressed_limit?(max_limit)
      uncompressed_size_positive? && uncompressed_size > max_limit
    end
  end

  # Manages size limits and validation for ZIP entries
  class SizeLimits
    attr_reader :max_entry_compressed, :max_entry_uncompressed, :max_total_uncompressed

    def initialize(max_entry_uncompressed:, max_entry_compressed:, max_total_uncompressed:)
      @max_entry_uncompressed = LimitResolver.resolve(
        max_entry_uncompressed,
        env: 'SHOKO_ZIP_MAX_ENTRY_BYTES',
        default: Limits::MAX_ENTRY_UNCOMPRESSED
      )
      @max_entry_compressed = LimitResolver.resolve(
        max_entry_compressed,
        env: 'SHOKO_ZIP_MAX_ENTRY_COMPRESSED_BYTES',
        default: Limits::MAX_ENTRY_COMPRESSED
      )
      @max_total_uncompressed = LimitResolver.resolve(
        max_total_uncompressed,
        env: 'SHOKO_ZIP_MAX_TOTAL_BYTES',
        default: Limits::MAX_TOTAL_UNCOMPRESSED
      )
      @total_uncompressed_bytes = 0
    end

    def enforce_entry_limits(entry, requested_name:)
      context = ValidationContext.new(entry, requested_name)
      validate_compressed_size(context)
      validate_uncompressed_size(context)
      validate_total_budget(context)
    end

    def enforce_uncompressed_budget(entry, actual_bytes)
      entry_name = entry.name
      validate_entry_size(entry_name, actual_bytes)
      validate_archive_budget(entry_name, actual_bytes)
    end

    def register_uncompressed_bytes(entry, byte_count)
      enforce_uncompressed_budget(entry, byte_count)
      increment_total(byte_count)
    end

    def current_total
      @total_uncompressed_bytes
    end

    private

    def increment_total(byte_count)
      @total_uncompressed_bytes += byte_count
    end

    def validate_compressed_size(context)
      return unless context.compressed_size > max_entry_compressed

      raise Error, "entry too large (compressed): #{context.requested_name}"
    end

    def validate_uncompressed_size(context)
      return unless context.exceeds_uncompressed_limit?(max_entry_uncompressed)

      raise Error, "entry too large (uncompressed): #{context.requested_name}"
    end

    def validate_total_budget(context)
      return unless context.uncompressed_size_positive?

      uncompressed_size = context.uncompressed_size
      new_total = current_total + uncompressed_size
      return unless new_total > max_total_uncompressed

      raise Error, "archive exceeds total uncompressed limit: #{context.requested_name}"
    end

    def validate_entry_size(entry_name, actual_bytes)
      return unless actual_bytes > max_entry_uncompressed

      raise Error, "entry too large after decompression: #{entry_name}"
    end

    def validate_archive_budget(entry_name, actual_bytes)
      new_total = current_total + actual_bytes
      return unless new_total > max_total_uncompressed

      raise Error, "archive exceeds total uncompressed limit: #{entry_name}"
    end
  end

  # Resolves limit values from arguments, environment, or defaults
  class LimitResolver
    def self.resolve(value, env:, default:)
      new(value, env, default).resolve
    end

    def initialize(value, env, default)
      @value = value
      @env = env
      @default = default
    end

    def resolve
      candidate = value_or_env
      parsed = parse_integer(candidate)
      valid_positive_or_default(parsed)
    end

    private

    def value_or_env
      @value || ENV.fetch(@env, nil)
    end

    def parse_integer(candidate)
      Integer(candidate)
    rescue StandardError
      nil
    end

    def valid_positive_or_default(parsed)
      parsed&.positive? ? parsed : @default
    end
  end

  # Tracks remaining bytes during chunk reading
  class ByteCounter
    def initialize(total_bytes)
      @remaining = total_bytes
    end

    attr_reader :remaining

    def remaining_positive?
      @remaining.positive?
    end

    def consume(byte_count)
      @remaining -= byte_count
    end
  end

  # Tracks remaining bytes during chunk reading
  class ChunkReader
    def initialize(io, total_bytes)
      @io = io
      @counter = ByteCounter.new(total_bytes)
    end

    def read_all_chunks
      chunks = []
      while @counter.remaining_positive?
        chunk = read_next_chunk
        chunks << chunk
      end
      chunks
    end

    def process_chunks_with(inflater, output)
      while @counter.remaining_positive?
        chunk = read_next_chunk
        output.append(inflater.inflate(chunk))
      end
    end

    private

    def read_next_chunk
      chunk = read_chunk_from_io
      validate_chunk(chunk)
      @counter.consume(chunk.bytesize)
      chunk
    end

    def read_chunk_from_io
      chunk_size = calculate_chunk_size
      @io.read(chunk_size)
    end

    def calculate_chunk_size
      remaining = @counter.remaining
      [remaining, Sizes::READ_CHUNK].min
    end

    def validate_chunk(chunk)
      raise Error, 'truncated compressed data' unless chunk && !chunk.empty?
    end
  end

  # Handles decompression of deflated ZIP entries
  class EntryDecompressor
    def self.create_inflater
      ::Zlib::Inflate.new(-::Zlib::MAX_WBITS)
    end

    def initialize(io, limits)
      @io = io
      @limits = limits
    end

    def inflate_deflated_entry(entry)
      remaining_bytes = entry.compressed_size.to_i
      with_inflater { |inflater| decompress_all(inflater, entry, remaining_bytes) }
    end

    private

    def with_inflater
      inflater = self.class.create_inflater
      yield inflater
    rescue ::Zlib::DataError => e
      raise Error, "invalid deflate data: #{e.message}"
    ensure
      close_inflater(inflater)
    end

    def close_inflater(inflater)
      inflater&.close
    rescue StandardError
      nil
    end

    def decompress_all(inflater, entry, remaining_bytes)
      output = DecompressionOutput.new(@limits, entry)
      reader = ChunkReader.new(@io, remaining_bytes)
      reader.process_chunks_with(inflater, output)
      output.finalize(inflater)
    end
  end

  # Accumulates decompressed data with budget enforcement
  class DecompressionOutput
    def initialize(limits, entry)
      @limits = limits
      @entry = entry
      @data = +''
    end

    def append(chunk)
      @data << chunk
      @limits.enforce_uncompressed_budget(@entry, @data.bytesize)
    end

    def finalize(inflater)
      @data << inflater.finish
      @data
    end
  end

  # Extracts variable-length fields from Local File Header
  class LocalFileHeaderParser
    LOCAL_HEADER_LENGTH_INDICES = [-2, -1].freeze

    def self.extract_lengths(header_bytes)
      field_values = header_bytes.unpack('v v v v v V V V v v')
      [field_values[LOCAL_HEADER_LENGTH_INDICES[0]], field_values[LOCAL_HEADER_LENGTH_INDICES[1]]]
    end
  end

  # Represents decompressed entry data with metadata
  class DecompressedData
    attr_reader :entry, :data

    def initialize(entry, data)
      @entry = entry
      @data = data
    end

    def verify_size
      expected_size = entry.uncompressed_size
      return unless expected_size&.positive?
      return if data.bytesize == expected_size

      raise Error, 'size mismatch after decompression'
    end

    def register_with_limits(limits)
      limits.register_uncompressed_bytes(entry, data.bytesize)
      encode_as_binary
    end

    def finalize_and_register(limits)
      verify_size
      register_with_limits(limits)
    end

    private

    def encode_as_binary
      data.force_encoding(Encoding::BINARY)
    end
  end

  # Encapsulates ZIP file state
  class FileState
    attr_reader :io, :entries, :limits

    def initialize(path, limits)
      @io = ::File.open(path, 'rb')
      @entries = {}
      @limits = limits
      @closed = false
    end

    def close
      return if @closed

      @io&.close
      @closed = true
    end

    def closed?
      @closed || !@io || @io.closed?
    end
  end

  # Handles reading entry data from ZIP file
  class EntryReader
    def initialize(io, limits)
      @io = io
      @limits = limits
    end

    def read_entry(entry)
      seek_to_entry_data(entry)
      raw_data = read_entry_payload(entry)
      decompressed = DecompressedData.new(entry, raw_data)
      decompressed.finalize_and_register(@limits)
    end

    private

    def seek_to_entry_data(entry)
      @io.seek(entry.local_header_offset, ::IO::SEEK_SET)
      verify_signature(Signatures::LOCAL_FILE, 'invalid local file header signature')
      skip_local_file_header
    end

    def skip_local_file_header
      header = read_exact(26, error_message: 'truncated local file header')
      name_length, extra_length = LocalFileHeaderParser.extract_lengths(header)
      @io.seek(name_length + extra_length, ::IO::SEEK_CUR)
    end

    def read_entry_payload(entry)
      compression_method = entry.compression_method
      case compression_method
      when 0 then read_stored_entry(entry)
      when 8 then decompress_deflated_entry(entry)
      else raise Error, "unsupported compression method: #{compression_method}"
      end
    end

    def read_stored_entry(entry)
      compressed_size = entry.compressed_size
      data = @io.read(compressed_size)
      return data if data && data.bytesize == compressed_size

      raise Error, 'truncated compressed data'
    end

    def decompress_deflated_entry(entry)
      decompressor = EntryDecompressor.new(@io, @limits)
      decompressor.inflate_deflated_entry(entry)
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

  # Read-only ZIP archive reader with explicit size safeguards.
  class File
    include IndexBuilder

    def self.open(path, **)
      zip_file = new(path, **)
      return zip_file unless block_given?

      begin
        yield zip_file
      ensure
        close_safely(zip_file)
      end
    end

    def self.close_safely(zip_file)
      zip_file.close
    rescue StandardError
      # ignore close errors
    end

    def initialize(path,
                   max_entry_uncompressed_bytes: nil,
                   max_entry_compressed_bytes: nil,
                   max_total_uncompressed_bytes: nil)
      limits = SizeLimits.new(
        max_entry_uncompressed: max_entry_uncompressed_bytes,
        max_entry_compressed: max_entry_compressed_bytes,
        max_total_uncompressed: max_total_uncompressed_bytes
      )
      @state = FileState.new(path, limits)
      @io = @state.io
      @entries = @state.entries
      build_index!
    rescue StandardError
      close
      raise
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

    def read(path)
      entry = find_entry_or_raise(path)
      validate_entry_readable(entry)
      limits = @state.limits
      limits.enforce_entry_limits(entry, requested_name: path)
      EntryReader.new(@state.io, limits).read_entry(entry)
    end

    private

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
