# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'fileutils'
require_relative '../base_adapter'

module Shoko
  module Adapters
    module Storage
      # Fetches and downloads dictionary files from the Wikdict SQLite index.
      class DictionaryCatalogService < Shoko::Adapters::BaseAdapter
        BASE_URL = 'https://download.wikdict.com/dictionaries/sqlite/2_2025-11/'

        class CatalogError < StandardError; end

        def list_remote
          response = request_index
          parse_index(response.body)
        end

        def download(entry, dest_dir)
          name = entry[:name] || entry['name'] || entry.to_s
          raise CatalogError, 'Missing dictionary filename' if name.to_s.strip.empty?

          url = entry[:url] || entry['url'] || URI.join(BASE_URL, name).to_s
          FileUtils.mkdir_p(dest_dir)
          dest_path = File.join(dest_dir, name)
          return { path: dest_path, existing: true } if File.exist?(dest_path)

          request_download(url, dest_path) { |done, total| yield(done, total) if block_given? }
          { path: dest_path, existing: false }
        end

        private

        def request_index
          uri = URI.parse(BASE_URL)
          request(uri)
        rescue StandardError => e
          raise CatalogError, e.message
        end

        def parse_index(body)
          items = []
          body.to_s.each_line do |line|
            next unless line.include?('.sqlite3')

            name = extract_name(line)
            next unless name

            date, time, size = extract_meta(line)
            source, target = parse_pair(name)
            items << {
              name: name,
              url: URI.join(BASE_URL, name).to_s,
              size: size,
              updated: [date, time].compact.join(' '),
              source: source,
              target: target,
            }
          end
          items.uniq { |item| item[:name] }.sort_by { |item| item[:name].to_s }
        end

        def extract_name(line)
          match = line.match(/href="([^"]+\.sqlite3)"/)
          match ? match[1] : nil
        end

        def extract_meta(line)
          meta = line.sub(/.*?<\/a>\s*/, '')
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

        def request_download(url, dest_path, limit = 2)
          uri = URI.parse(url)
          response = request(uri) do |http|
            http.request(Net::HTTP::Get.new(uri)) do |resp|
              if resp.is_a?(Net::HTTPSuccess)
                stream_response(resp, dest_path) { |done, total| yield(done, total) if block_given? }
              end
              resp
            end
          end

          if response.is_a?(Net::HTTPRedirection) && limit.positive?
            redirect = URI.join(uri.to_s, response['location']).to_s
            return request_download(redirect, dest_path, limit - 1) { |done, total| yield(done, total) if block_given? }
          end

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

        def request(uri, &block)
          raise CatalogError, "Invalid URL: #{uri}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 15
          if block_given?
            http.start(&block)
          else
            http.get(uri.request_uri)
          end
        rescue StandardError => e
          logger&.error('dictionary_catalog_request_failed', error: e.message, url: uri.to_s)
          raise CatalogError, e.message
        end
      end
    end
  end
end
