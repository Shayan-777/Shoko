# frozen_string_literal: true

require 'uri'

module Shoko
  module Adapters
    module Rss
      # Parses the URLs that appear in feeds, which are IRIs rather than URIs.
      #
      # `URI.parse` rejects any address containing a non-ASCII character
      # ("URI must be ascii only"), but real feeds are full of them: a German
      # news slug like `.../drohne-ins-klassenzimmer-einschlägt/a-78076700` is
      # entirely ordinary. Browsers percent-encode those characters and request
      # the encoded form; this does the same, so such an address is fetched
      # instead of raising.
      #
      # Only non-ASCII characters are encoded. Existing percent escapes, the
      # reserved delimiters (`/ ? & = #`), and everything else pass through
      # untouched, so an already-encoded URL is never double-encoded.
      module HttpUri
        module_function

        # @param value [String] address as it appeared in the feed
        # @return [URI::Generic]
        # @raise [URI::InvalidURIError] when the address is malformed for
        #   reasons other than non-ASCII characters
        def parse(value)
          URI.parse(encode(value.to_s))
        end

        # @return [String] the address with non-ASCII characters percent-encoded
        def encode(value)
          return value if value.ascii_only?

          value.each_char.map { |char| char.ascii_only? ? char : percent_encode(char) }.join
        end

        def percent_encode(char)
          char.each_byte.map { |byte| format('%%%02X', byte) }.join
        end
      end
    end
  end
end
