# frozen_string_literal: true

require_relative 'error'

module Shoko
  module Zip
    # Strict reads over a zip archive's IO: a short read is a truncated or
    # corrupt archive, never a partial success, and a signature mismatch is a
    # structural error.
    #
    # The reader and the archive facade both parse fixed-width records off the
    # same IO and both need exactly these two guarantees.
    module ExactIo
      module_function

      # @raise [Shoko::Zip::Error] when fewer than byte_count bytes remain
      def read_exact(io, byte_count, error_message:)
        data = io.read(byte_count)
        return data if data && data.bytesize == byte_count

        raise Error, error_message
      end

      # @raise [Shoko::Zip::Error] when the next bytes are not the signature
      def verify_signature(io, expected_signature, error_message)
        signature_bytes = io.read(expected_signature.bytesize)
        raise Error, error_message unless signature_bytes == expected_signature
      end
    end
  end
end
