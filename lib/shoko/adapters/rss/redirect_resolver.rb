# frozen_string_literal: true

require 'uri'

require_relative 'http_uri'

module Shoko
  module Adapters
    module Rss
      # Resolves an HTTP `Location` header against the URI it was served from.
      #
      # Both RSS fetchers (feed and article) follow redirects and need the same
      # relative-vs-absolute resolution, including the same tolerance for a
      # malformed Location value.
      module RedirectResolver
        module_function

        # @param uri [URI] the URI the redirect was served from
        # @param location [String] raw Location header value
        # @return [URI] absolute target URI
        def resolve(uri, location)
          parsed = HttpUri.parse(location)
          return uri + parsed.to_s if parsed.relative?

          parsed
        rescue URI::InvalidURIError
          uri + location
        end
      end
    end
  end
end
