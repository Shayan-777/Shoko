# frozen_string_literal: true

require 'net/http'
require 'uri'

require_relative '../../base_adapter'

module Shoko
  module Adapters
    module BookSources
      class LibgenClient < Shoko::Adapters::BaseAdapter
        # HTTP transport and URI normalization helpers for Libgen requests.
        module Transport
          private

          def request_body(uri, limit = 2)
            response = request(uri)
            return response.body if response.is_a?(Net::HTTPSuccess)
            return request_body(redirect_uri(uri, response, limit), limit - 1) if redirect_response?(response, limit)

            raise Error, "Request failed (#{response.code})"
          end

          def request_download(uri, dest_path, limit = 2)
            response = download_response(uri, dest_path) { |done, total| yield(done, total) if block_given? }
            if redirect_response?(response, limit)
              redirect = redirect_uri(uri, response, limit)
              return request_download(redirect, dest_path, limit - 1) do |done, total|
                yield(done, total) if block_given?
              end
            end
            return response if response.is_a?(Net::HTTPSuccess)

            raise Error, "Download failed (#{response.code})"
          end

          def download_response(uri, dest_path)
            request(uri) do |http|
              http.request(Net::HTTP::Get.new(uri.request_uri, request_headers)) do |response|
                handle_download_response(response, dest_path) { |done, total| yield(done, total) if block_given? }
              end
            end
          end

          def handle_download_response(response, dest_path)
            return response unless response.is_a?(Net::HTTPSuccess)

            stream_response(response, dest_path) { |done, total| yield(done, total) if block_given? }
            response
          end

          def redirect_response?(response, limit)
            response.is_a?(Net::HTTPRedirection) && limit.positive?
          end

          def redirect_uri(uri, response, limit)
            raise Error, "Request failed (#{response.code})" unless redirect_response?(response, limit)

            resolve_redirect_uri(uri, response['location'])
          end

          def stream_response(response, dest_path)
            total = response['Content-Length'].to_i
            downloaded = 0
            File.open(dest_path, 'wb') do |file|
              response.read_body do |chunk|
                file.write(chunk)
                downloaded += chunk.bytesize
                yield(downloaded, total) if block_given?
              end
            end
          end

          def request(uri, &block)
            ensure_http_dependencies!
            normalized = normalize_uri(uri, base: @base_url)
            validate_http_uri!(normalized)

            http = build_http_client(normalized)
            block ? http.start(&block) : http.get(normalized.request_uri, request_headers)
          rescue Error, IOError, SystemCallError, SocketError, Timeout::Error => e
            log_error('libgen_request_failed', error: e.message, url: uri.to_s)
            raise Error, e.message
          end

          def validate_http_uri!(normalized)
            return if normalized.is_a?(URI::HTTP) || normalized.is_a?(URI::HTTPS)

            raise Error, "Invalid URL: #{normalized}"
          end

          def build_http_client(normalized)
            http = Net::HTTP.new(normalized.host, normalized.port)
            http.use_ssl = normalized.scheme == 'https'
            http.open_timeout = @open_timeout
            http.read_timeout = @read_timeout
            http
          end

          def request_headers
            { 'User-Agent' => USER_AGENT }
          end

          def normalize_uri(input, base: nil)
            uri = input.is_a?(URI) ? input : URI.parse(input.to_s)
            return uri if http_uri?(uri)

            base ? URI.join(base.to_s, uri.to_s) : fallback_uri(uri)
          end

          def http_uri?(uri)
            uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          end

          def fallback_uri(uri)
            return uri unless uri.scheme.nil? && uri.host.nil?

            candidate = uri.to_s
            return URI.parse("https:#{candidate}") if candidate.start_with?('//')
            return URI.parse("https://#{candidate}") if host_like_candidate?(candidate)

            uri
          end

          def host_like_candidate?(candidate)
            /\A[a-z0-9.-]+\.[a-z]{2,}/i.match?(candidate)
          end

          def safe_normalize_uri(input, base:)
            normalize_uri(input, base: base)
          rescue URI::InvalidURIError => e
            log_error('libgen_invalid_uri', error: e.message, url: input.to_s)
            nil
          end

          def uri_query(url)
            return nil if url.to_s.strip.empty?

            URI.parse(url).query
          rescue URI::InvalidURIError => e
            log_error('libgen_invalid_uri', error: e.message, url: url.to_s)
            nil
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
end
