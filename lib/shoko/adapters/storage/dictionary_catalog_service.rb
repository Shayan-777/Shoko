# frozen_string_literal: true

require 'fileutils'
require_relative '../base_adapter'
require_relative '../../shared/errors'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Storage
      # Fetches and downloads dictionary files from the Wikdict SQLite index.
      class DictionaryCatalogService < Shoko::Adapters::BaseAdapter
        BASE_URL = 'https://download.wikdict.com/dictionaries/sqlite/2_2025-11/'

        class CatalogError < Shoko::Error; end

        def list_remote
          response = request_index
          parse_index(response.body)
        end

        def download(entry, dest_dir)
          normalized = normalize_entry(entry)
          name = normalized[:name] || entry.to_s
          raise CatalogError, 'Missing dictionary filename' if name.to_s.strip.empty?

          url = normalized[:url] || URI.join(BASE_URL, name).to_s
          FileUtils.mkdir_p(dest_dir)
          dest_path = File.join(dest_dir, name)
          return { path: dest_path, existing: true } if File.exist?(dest_path)

          request_download(url, dest_path) { |done, total| yield(done, total) if block_given? }
          { path: dest_path, existing: false }
        end

        private

        def request_index
          ensure_http_dependencies!
          uri = URI.parse(BASE_URL)
          request(uri)
        rescue URI::InvalidURIError, CatalogError, IOError, SystemCallError,
               SocketError, Timeout::Error
          raise CatalogError, $ERROR_INFO.message
        end

        def parse_index(body)
          body.to_s.each_line
              .filter_map { |line| catalog_item_from_line(line) }
              .uniq { |item| item[:name] }
              .sort_by { |item| item[:name].to_s }
        end

        def extract_name(line)
          match = line.match(/href="([^"]+\.sqlite3)"/)
          match ? match[1] : nil
        end

        def extract_meta(line)
          meta = line.sub(%r{.*?</a>\s*}, '')
          parts = meta.split
          date = parts[0]
          time = parts[1]
          size = parts[2]
          [date, time, size]
        end

        def parse_pair(name)
          base = File.basename(name, '.sqlite3')
          parts = base.split('-')
          return [nil, nil] unless parts.length == 2

          [parts[0], parts[1]]
        end

        def normalize_entry(entry)
          return {} unless entry.is_a?(Hash)

          Shoko::Shared::HashNormalizer.deep_symbolize(entry)
        end

        def request_download(url, dest_path, limit = 2, &)
          ensure_http_dependencies!
          uri = URI.parse(url)
          response = download_response(uri, dest_path, &)
          return follow_download_redirect(uri, response, dest_path, limit, &) if redirect?(response) && limit.positive?

          return response if response.is_a?(Net::HTTPSuccess)

          raise CatalogError, "Download failed (#{response.code})"
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

        def request(uri, &)
          validate_request_uri!(uri)
          perform_request(uri, &)
        rescue CatalogError, IOError, SystemCallError, SocketError, Timeout::Error
          logger&.error('dictionary_catalog_request_failed', error: $ERROR_INFO.message, url: uri.to_s)
          raise CatalogError, $ERROR_INFO.message
        end

        def ensure_http_dependencies!
          return if defined?(Net::HTTP) && defined?(URI::DEFAULT_PARSER)

          require 'net/http'
          require 'uri'
        end

        def catalog_item_from_line(line)
          return unless line.include?('.sqlite3')

          name = extract_name(line)
          return unless name

          date, time, size = extract_meta(line)
          source, target = parse_pair(name)
          {
            name: name,
            url: URI.join(BASE_URL, name).to_s,
            size: size,
            updated: [date, time].compact.join(' '),
            source: source,
            target: target,
          }
        end

        def download_response(uri, dest_path)
          request(uri) do |http|
            http.request(Net::HTTP::Get.new(uri)) do |resp|
              stream_response(resp, dest_path) { |done, total| yield(done, total) if block_given? }
              resp
            end
          end
        end

        def follow_download_redirect(uri, response, dest_path, limit)
          redirect = URI.join(uri.to_s, response['location']).to_s
          request_download(redirect, dest_path, limit - 1) { |done, total| yield(done, total) if block_given? }
        end

        def redirect?(response)
          response.is_a?(Net::HTTPRedirection)
        end

        def validate_request_uri!(uri)
          return if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          raise CatalogError, "Invalid URL: #{uri}"
        end

        def perform_request(uri, &)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 15
          return http.start(&) if block_given?

          http.get(uri.request_uri)
        end
      end
    end
  end
end
