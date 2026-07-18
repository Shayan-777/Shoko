# frozen_string_literal: true

module Shoko
  module Zip
    # ZIP file format signature constants
    module Signatures
      EOCD = [0x06054B50].pack('V').freeze # "PK\x05\x06"
      CENTRAL_DIR = [0x02014B50].pack('V').freeze # "PK\x01\x02"
      LOCAL_FILE = [0x04034B50].pack('V').freeze # "PK\x03\x04"
    end
  end
end
