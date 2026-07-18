# frozen_string_literal: true

module Shoko
  module Zip
    # Default size limit constants
    module Limits
      MAX_ENTRY_COMPRESSED = 64 * 1024 * 1024
      MAX_ENTRY_UNCOMPRESSED = 64 * 1024 * 1024
      MAX_TOTAL_UNCOMPRESSED = 256 * 1024 * 1024
    end
  end
end
