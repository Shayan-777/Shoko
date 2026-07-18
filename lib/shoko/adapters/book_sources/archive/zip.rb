# frozen_string_literal: true

# Minimal, read-only ZIP reader compatible with the subset of rubyzip API
# used by this project. Supports STORE (0) and DEFLATE (8) entries.
#
# Public API:
#   Shoko::Zip::File.open(path) { |zip| ... }
#   zip.entries -> Array<Shoko::Zip::Entry>
#   zip.read(entry_path) -> String (binary)
#   zip.find_entry(entry_path) -> entry or nil
#   zip.close ; zip.closed?
#   Shoko::Zip::Error raised for malformed/unsupported archives or missing entries

require_relative 'zip/byte_counter'
require_relative 'zip/central_directory_header_parser'
require_relative 'zip/central_directory_variable_fields'
require_relative 'zip/chunk_reader'
require_relative 'zip/decompressed_data'
require_relative 'zip/decompression_output'
require_relative 'zip/entry'
require_relative 'zip/entry_decompressor'
require_relative 'zip/entry_factory'
require_relative 'zip/entry_reader'
require_relative 'zip/eocd_parser'
require_relative 'zip/error'
require_relative 'zip/file'
require_relative 'zip/file_state'
require_relative 'zip/limit_resolver'
require_relative 'zip/limits'
require_relative 'zip/local_file_header_parser'
require_relative 'zip/name_normalizer'
require_relative 'zip/signatures'
require_relative 'zip/size_limits'
require_relative 'zip/sizes'
require_relative 'zip/validation_context'
