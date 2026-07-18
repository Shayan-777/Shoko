# frozen_string_literal: true

module Shoko
  module Zip
    # Metadata for a Central Directory entry.
    Entry = Struct.new(
      :name,
      :compressed_size,
      :uncompressed_size,
      :crc32,
      :compression_method,
      :gp_flags,
      :local_header_offset
    )
  end
end
