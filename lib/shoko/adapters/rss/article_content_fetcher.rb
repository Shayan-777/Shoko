# frozen_string_literal: true

require 'net/http'
require 'stringio'
require 'uri'
require 'zlib'

require_relative '../../shared/errors'
require_relative '../../shared/version'
require_relative '../base_adapter'
require_relative 'article_content_extractor'

module Shoko
  module Adapters
    module Rss
      # Fetches linked article HTML pages and extracts readable body content.
      class ArticleContentFetcher < Shoko::Adapters::BaseAdapter
        class FetchError < Shoko::Error; end

        USER_AGENT = "Shoko RSS Reader/#{Shoko::VERSION}".freeze

        def initialize(extractor: ArticleContentExtractor.new, open_timeout: 5, read_timeout: 10, redirect_limit: 3,
                       logger: nil)
          super(logger: logger)
          @extractor = extractor
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @redirect_limit = redirect_limit
        end

        def fetch(url)
          uri = normalize_uri(url)
          response, = perform_request(uri, redirects_left: @redirect_limit)
          unless response.is_a?(Net::HTTPSuccess)
            raise FetchError, "Article request failed: #{response.code} #{response.message}"
          end

          @extractor.extract(decoded_body(response))
        rescue SocketError, SystemCallError, IOError, Timeout::Error, URI::InvalidURIError => e
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

        def request(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout

          request = Net::HTTP::Get.new(uri)
          request['User-Agent'] = USER_AGENT
          request['Accept'] = 'text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8'
          request['Accept-Encoding'] = 'gzip,deflate'

          http.start { |session| session.request(request) }
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
          return body if encoding.empty?
          return Zlib::GzipReader.new(StringIO.new(body)).read if encoding.include?('gzip')
          return Zlib::Inflate.inflate(body) if encoding.include?('deflate')

          body
        rescue Zlib::Error
          undecoded_body(body)
        end

        def undecoded_body(body)
          body
        end
      end
    end
  end
end
