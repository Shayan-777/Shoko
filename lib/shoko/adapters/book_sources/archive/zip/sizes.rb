# frozen_string_literal: true

module Shoko
  module Zip
    # ZIP file format size constants
    module Sizes
      MAX_EOCD_SCAN = 66_560 # 64 KiB comment + 2 KiB buffer
      READ_CHUNK = 16 * 1024
    end
  end
end
