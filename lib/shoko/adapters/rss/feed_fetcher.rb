# frozen_string_literal: true

require 'net/http'
require 'uri'

require_relative '../../shared/errors'
require_relative '../../shared/version'
require_relative '../base_adapter'
require_relative 'bounded_http_body'
require_relative 'feed_parser'

module Shoko
  module Adapters
    module Rss
      # Fetches remote RSS/Atom feeds over HTTP and normalizes transport concerns.
      class FeedFetcher < Shoko::Adapters::BaseAdapter
        class FetchError < Shoko::Error; end

        USER_AGENT = "Shoko RSS Reader/#{Shoko::VERSION}".freeze
        MAX_BODY_BYTES = 8 * 1024 * 1024
        MAX_DECOMPRESSED_BYTES = 32 * 1024 * 1024

        def initialize(parser: FeedParser.new, open_timeout: 5, read_timeout: 10, redirect_limit: 3, logger: nil,
                       max_body_bytes: MAX_BODY_BYTES, max_decompressed_bytes: MAX_DECOMPRESSED_BYTES)
          super(logger: logger)
          @parser = parser
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @redirect_limit = redirect_limit
          @max_body_bytes = max_body_bytes
          @max_decompressed_bytes = max_decompressed_bytes
        end

        def fetch(url, etag: nil, last_modified: nil)
          response, final_uri = fetch_response(url, etag: etag, last_modified: last_modified)
          return not_modified_payload(response, final_uri, etag, last_modified) if not_modified_response?(response)
          raise FetchError, request_error_message(response) unless success_response?(response)

          build_fetch_payload(response, final_uri)
        rescue BoundedHttpBody::TooLarge, SocketError, SystemCallError, IOError, Timeout::Error,
               URI::InvalidURIError => e
          raise FetchError, e.message
        end

        private

        def fetch_response(url, etag:, last_modified:)
          uri = normalize_uri(url)
          perform_request(uri, etag: etag, last_modified: last_modified, redirects_left: @redirect_limit)
        end

        def perform_request(uri, etag:, last_modified:, redirects_left:)
          response = request(uri, etag: etag, last_modified: last_modified)
          return [response, uri] if response.is_a?(Net::HTTPNotModified)

          if response.is_a?(Net::HTTPRedirection)
            raise FetchError, 'Too many feed redirects' if redirects_left <= 0

            location = response['location'].to_s.strip
            raise FetchError, 'Feed redirect is missing a location' if location.empty?

            return perform_request(resolve_redirect(uri, location),
                                   etag: etag,
                                   last_modified: last_modified,
                                   redirects_left: redirects_left - 1)
          end

          [response, uri]
        end

        # Block-form request so the body is read in bounded chunks; without
        # it Net::HTTP buffers the entire (possibly unbounded) body before
        # any size check could run.
        def request(uri, etag:, last_modified:)
          request = build_request(uri, etag: etag, last_modified: last_modified)
          http_client(uri).start do |session|
            session.request(request) do |response|
              response.body = BoundedHttpBody.read(response, limit: @max_body_bytes) if response.is_a?(Net::HTTPSuccess)
            end
          end
        end

        def http_client(uri)
          Net::HTTP.new(uri.host, uri.port).tap do |http|
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = @open_timeout
            http.read_timeout = @read_timeout
          end
        end

        def build_request(uri, etag:, last_modified:)
          Net::HTTP::Get.new(uri).tap do |request|
            apply_default_headers(request)
            apply_cache_headers(request, etag: etag, last_modified: last_modified)
          end
        end

        def apply_default_headers(request)
          request['User-Agent'] = USER_AGENT
          request['Accept'] = 'application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8'
          request['Accept-Encoding'] = 'gzip,deflate'
        end

        def apply_cache_headers(request, etag:, last_modified:)
          request['If-None-Match'] = etag.to_s unless etag.to_s.strip.empty?
          request['If-Modified-Since'] = last_modified.to_s unless last_modified.to_s.strip.empty?
        end

        def normalize_uri(value)
          candidate = value.to_s.strip
          raise FetchError, 'Feed URL is required' if candidate.empty?

          candidate = "https:#{candidate}" if candidate.start_with?('//')
          candidate = "https://#{candidate}" if candidate.match?(%r{\A[a-z0-9.-]+\.[a-z]{2,}([/:?#].*)?\z}i)
          uri = URI.parse(candidate)
          raise FetchError, 'Feed URL must use http or https' unless %w[http https].include?(uri.scheme)
          raise FetchError, 'Feed URL host is missing' if uri.host.to_s.strip.empty?

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

        def not_modified_payload(response, uri, etag, last_modified)
          {
            not_modified: true,
            url: uri.to_s,
            etag: response['etag'] || etag,
            last_modified: response['last-modified'] || last_modified,
            articles: [],
          }
        end

        def success_response?(response)
          response.is_a?(Net::HTTPSuccess)
        end

        def not_modified_response?(response)
          response.is_a?(Net::HTTPNotModified)
        end

        def request_error_message(response)
          "Feed request failed: #{response.code} #{response.message}"
        end

        def build_fetch_payload(response, final_uri)
          parsed = @parser.parse(decoded_body(response))
          {
            not_modified: false,
            url: final_uri.to_s,
            title: parsed[:title],
            site_url: parsed[:site_url],
            etag: response['etag'],
            last_modified: response['last-modified'],
            articles: Array(parsed[:articles]),
          }
        end
      end
    end
  end
end
