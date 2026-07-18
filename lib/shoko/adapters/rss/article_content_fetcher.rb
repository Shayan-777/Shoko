# frozen_string_literal: true

require 'net/http'
require 'uri'

require_relative '../../shared/errors'
require_relative '../../shared/version'
require_relative '../base_adapter'
require_relative 'article_content_extractor'
require_relative 'bounded_http_body'

module Shoko
  module Adapters
    module Rss
      # Fetches linked article HTML pages and extracts readable body content.
      class ArticleContentFetcher < Shoko::Adapters::BaseAdapter
        class FetchError < Shoko::Error; end

        USER_AGENT = "Shoko RSS Reader/#{Shoko::VERSION}".freeze
        MAX_BODY_BYTES = 8 * 1024 * 1024
        MAX_DECOMPRESSED_BYTES = 32 * 1024 * 1024

        def initialize(extractor: ArticleContentExtractor.new, open_timeout: 5, read_timeout: 10, redirect_limit: 3,
                       logger: nil, max_body_bytes: MAX_BODY_BYTES, max_decompressed_bytes: MAX_DECOMPRESSED_BYTES)
          super(logger: logger)
          @extractor = extractor
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @redirect_limit = redirect_limit
          @max_body_bytes = max_body_bytes
          @max_decompressed_bytes = max_decompressed_bytes
        end

        def fetch(url)
          uri = normalize_uri(url)
          response, = perform_request(uri, redirects_left: @redirect_limit)
          unless response.is_a?(Net::HTTPSuccess)
            raise FetchError, "Article request failed: #{response.code} #{response.message}"
          end

          @extractor.extract(decoded_body(response))
        rescue BoundedHttpBody::TooLarge, SocketError, SystemCallError, IOError, Timeout::Error,
               URI::InvalidURIError => e
          raise FetchError, e.message
        end

        private

        def perform_request(uri, redirects_left:)
          response = request(uri)
          if response.is_a?(Net::HTTPRedirection)
            raise FetchError, 'Too many article redirects' if redirects_left <= 0

            location = response['location'].to_s.strip
            raise FetchError, 'Article redirect is missing a location' if location.empty?

            return perform_request(resolve_redirect(uri, location), redirects_left: redirects_left - 1)
          end

          [response, uri]
        end

        # Block-form request so the body is read in bounded chunks; without
        # it Net::HTTP buffers the entire (possibly unbounded) body before
        # any size check could run.
        def request(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout

          request = Net::HTTP::Get.new(uri)
          request['User-Agent'] = USER_AGENT
          request['Accept'] = 'text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8'
          request['Accept-Encoding'] = 'gzip,deflate'

          http.start do |session|
            session.request(request) do |response|
              response.body = BoundedHttpBody.read(response, limit: @max_body_bytes) if response.is_a?(Net::HTTPSuccess)
            end
          end
        end

        def normalize_uri(value)
          candidate = value.to_s.strip
          raise FetchError, 'Article URL is required' if candidate.empty?

          uri = URI.parse(candidate)
          raise FetchError, 'Article URL must use http or https' unless %w[http https].include?(uri.scheme)
          raise FetchError, 'Article URL host is missing' if uri.host.to_s.strip.empty?

          uri
        end

        def resolve_redirect(uri, location)
          parsed = URI.parse(location)
          return uri + parsed.to_s if parsed.relative?

          parsed
        rescue URI::InvalidURIError
          uri + location
        end

        def decoded_body(response)
          body = response.body.to_s
          encoding = response['content-encoding'].to_s.downcase
          BoundedHttpBody.decompress(body, encoding, limit: @max_decompressed_bytes)
        end
      end
    end
  end
end
