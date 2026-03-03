# frozen_string_literal: true

require 'json'

module Shoko
  module Adapters
    module BookSources
      # Thin HTTP client for the Gutendex API.
      class GutendexClient
        class Error < StandardError; end

        API_ROOT = 'https://gutendex.com/books'

        def initialize(logger: nil, open_timeout: 5, read_timeout: 15)
          @logger = logger
          @open_timeout = open_timeout
          @read_timeout = read_timeout
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

        def request_download(uri, dest_path, limit = 2, &on_progress)
          ensure_http_dependencies!
          response = request(uri) do |http|
            http.request(Net::HTTP::Get.new(uri)) do |resp|
              if resp.is_a?(Net::HTTPSuccess)
                stream_response(resp, dest_path, &on_progress)
              else
                resp
              end
            end
          end

          if response.is_a?(Net::HTTPRedirection) && limit.positive?
            redirect = resolve_redirect_uri(uri, response['location'])
            return request_download(redirect, dest_path, limit - 1, &on_progress)
          end

          return response if response.is_a?(Net::HTTPSuccess)

          raise Error, "Download failed (#{response.code})"
        end

        def stream_response(response, dest_path)
          return response unless response.is_a?(Net::HTTPSuccess)

          total = response['Content-Length'].to_i
          downloaded = 0
          File.open(dest_path, 'wb') do |file|
            response.read_body do |chunk|
              file.write(chunk)
              downloaded += chunk.bytesize
              yield(downloaded, total) if block_given?
            end
          end
          response
        end

        def request(uri, &)
          ensure_http_dependencies!
          uri = normalize_uri(uri, base: API_ROOT)
          raise Error, "Invalid URL: #{uri}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          if block_given?
            http.start(&)
          else
            http.get(uri.request_uri)
          end
        rescue Shoko::Error => e
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
        rescue URI::Error
          raise
        end

        def try_infer_scheme(uri)
          return nil unless uri.scheme.nil? && uri.host.nil?

          candidate = add_scheme_if_needed(uri.to_s)
          parsed = URI.parse(candidate)
          http_uri?(parsed) ? parsed : nil
        rescue URI::Error
          raise
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

        def ensure_http_dependencies!
          return if defined?(Net::HTTP) && defined?(URI::DEFAULT_PARSER)

          require 'net/http'
          require 'uri'
        end
      end
    end
  end
end
