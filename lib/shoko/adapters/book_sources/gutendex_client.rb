# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module BookSources
      # Thin HTTP client for the Gutendex API.
      class GutendexClient
        class Error < Shoko::Error; end

        API_ROOT = 'https://gutendex.com/books'
        MAX_JSON_BODY_BYTES = 4 * 1024 * 1024
        MAX_DOWNLOAD_BYTES = 200 * 1024 * 1024

        def initialize(logger: nil, open_timeout: 5, read_timeout: 15,
                       max_json_body_bytes: MAX_JSON_BODY_BYTES, max_download_bytes: MAX_DOWNLOAD_BYTES)
          @logger = logger
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @max_json_body_bytes = max_json_body_bytes
          @max_download_bytes = max_download_bytes
        end

        def search(query:, page_url: nil)
          ensure_http_dependencies!
          uri = page_url ? normalize_uri(page_url, base: API_ROOT) : build_query_uri(query)
          request_json(uri)
        end

        def download(url, dest_path, &)
          ensure_http_dependencies!
          uri = normalize_uri(url, base: API_ROOT)
          request_download(uri, dest_path, &)
        end

        private

        def build_query_uri(query)
          uri = URI.parse(API_ROOT)
          q = query.to_s.strip
          uri.query = URI.encode_www_form(search: q) unless q.empty?
          uri
        end

        def request_json(uri, limit = 2)
          response = request(uri)
          return parse_json(response) if response.is_a?(Net::HTTPSuccess)

          if response.is_a?(Net::HTTPRedirection) && limit.positive?
            redirect = resolve_redirect_uri(uri, response['location'])
            return request_json(redirect, limit - 1)
          end

          raise Error, "Request failed (#{response.code})"
        end

        def parse_json(response)
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise Error, "Invalid JSON response: #{e.message}"
        end

        def request_download(uri, dest_path, limit = 2, &)
          ensure_http_dependencies!
          response = download_response(uri, dest_path, &)

          if response.is_a?(Net::HTTPRedirection) && limit.positive?
            redirect = resolve_redirect_uri(uri, response['location'])
            return request_download(redirect, dest_path, limit - 1, &)
          end

          return response if response.is_a?(Net::HTTPSuccess)

          raise Error, "Download failed (#{response.code})"
        end

        # Streams into an adjacent .part file and renames only after the body
        # completed, so an interrupted or cancelled download never leaves a
        # truncated file at the final path (which would then be treated as a
        # finished download forever).
        def stream_response(response, dest_path)
          return response unless response.is_a?(Net::HTTPSuccess)

          part_path = "#{dest_path}.part"
          begin
            stream_body_to(response, part_path) { |done, total| yield(done, total) if block_given? }
            File.rename(part_path, dest_path)
          ensure
            FileUtils.rm_f(part_path)
          end
          response
        end

        def stream_body_to(response, part_path)
          total = response['Content-Length'].to_i
          downloaded = 0
          File.open(part_path, 'wb') do |file|
            response.read_body do |chunk|
              if downloaded + chunk.bytesize > @max_download_bytes
                raise Error, "Download exceeded #{@max_download_bytes} bytes"
              end

              file.write(chunk)
              downloaded += chunk.bytesize
              yield(downloaded, total) if block_given?
            end
          end
        end

        def request(uri, &)
          ensure_http_dependencies!
          uri = normalize_uri(uri, base: API_ROOT)
          validate_uri!(uri)
          perform_request(uri, &)
        rescue Error, IOError, SystemCallError, SocketError, Timeout::Error => e
          @logger&.error('Gutendex request failed', error: e.message, url: uri.to_s)
          raise Error, e.message
        end

        def normalize_uri(input, base: nil)
          uri = parse_uri(input)
          return uri if http_uri?(uri)

          joined = try_join_with_base(uri, base)
          return joined if joined

          inferred = try_infer_scheme(uri)
          inferred || uri
        end

        def parse_uri(input)
          input.is_a?(URI) ? input : URI.parse(input.to_s)
        end

        def http_uri?(uri)
          uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        end

        def try_join_with_base(uri, base)
          return nil unless base

          base_uri = parse_uri(base)
          joined = URI.join(base_uri.to_s, uri.to_s)
          http_uri?(joined) ? joined : nil
        end

        def try_infer_scheme(uri)
          return nil unless uri.scheme.nil? && uri.host.nil?

          candidate = add_scheme_if_needed(uri.to_s)
          parsed = URI.parse(candidate)
          http_uri?(parsed) ? parsed : nil
        end

        def add_scheme_if_needed(str)
          if str.start_with?('//')
            "https:#{str}"
          elsif /\A[a-z0-9.-]+\.[a-z]{2,}/i.match?(str)
            "https://#{str}"
          else
            str
          end
        end

        def resolve_redirect_uri(base_uri, location)
          normalize_uri(location, base: base_uri)
        end

        def download_response(uri, dest_path, &)
          request(uri) do |http|
            http.request(Net::HTTP::Get.new(uri)) do |resp|
              stream_response(resp, dest_path, &) if resp.is_a?(Net::HTTPSuccess)
              resp
            end
          end
        end

        def validate_uri!(uri)
          return if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          raise Error, "Invalid URL: #{uri}"
        end

        # The non-block branch serves the JSON API paths; reading in bounded
        # chunks caps what a broken or malicious server can make us buffer.
        def perform_request(uri, &)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          return http.start(&) if block_given?

          http.start do |session|
            session.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
              response.body = read_bounded_json_body(response) if response.is_a?(Net::HTTPSuccess)
            end
          end
        end

        def read_bounded_json_body(response)
          buffer = +''
          response.read_body do |chunk|
            if buffer.bytesize + chunk.bytesize > @max_json_body_bytes
              raise Error, "Response exceeded #{@max_json_body_bytes} bytes"
            end

            buffer << chunk
          end
          buffer
        end

        def ensure_http_dependencies!
          return if defined?(Net::HTTP) && defined?(URI::DEFAULT_PARSER)

          require 'net/http'
          require 'uri'
        end
      end
    end
  end
end
