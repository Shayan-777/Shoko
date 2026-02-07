# frozen_string_literal: true

require 'fileutils'
require_relative '../base_adapter'

module Shoko
  module Adapters::BookSources
    # Coordinates Gutendex search + download to the local library.
    class DownloadService < Shoko::Adapters::BaseAdapter
      class DownloadError < StandardError; end

      # @param gutendex_client [Object] Client for Gutendex API
      # @param logger [Object, nil] Optional logger
      def initialize(gutendex_client:, downloads_root: nil, logger: nil)
        super(logger: logger)
        @client = gutendex_client
        @downloads_root = downloads_root
      end

      def search(query:, page_url: nil)
        payload = @client.search(query: query, page_url: page_url)
        {
          count: payload['count'].to_i,
          next: payload['next'],
          previous: payload['previous'],
          books: normalize_books(payload['results']),
        }
      end

      def download(book)
        url = pick_download_url(book)
        raise DownloadError, 'No EPUB format available' unless url

        dest_dir = downloads_root
        FileUtils.mkdir_p(dest_dir)
        dest_path = File.join(dest_dir, filename_for(book))
        return { path: dest_path, existing: true } if File.exist?(dest_path)

        @client.download(url, dest_path) { |done, total| yield(done, total) if block_given? }
        { path: dest_path, existing: false }
      end

      private

      def downloads_root
        @downloads_root ||= Shoko::Adapters::Storage::ConfigPaths.downloads_root
      end

      def normalize_books(items)
        Array(items).map do |raw|
          {
            id: raw['id'],
            title: raw['title'],
            authors: Array(raw['authors']).filter_map { |a| a['name'] },
            languages: Array(raw['languages']).map(&:to_s),
            download_count: raw['download_count'],
            formats: raw['formats'] || {},
          }
        end
      end

      def pick_download_url(book)
        formats = value_for(book, :formats, 'formats', {})
        return nil unless formats.respond_to?(:each)

        keys = formats.keys.map(&:to_s)
        epub_key = keys.find { |k| k.start_with?('application/epub+zip') } ||
                   keys.find { |k| k.include?('application/epub') } ||
                   keys.find { |k| k.include?('epub') }
        return nil unless epub_key

        formats[epub_key] || formats[epub_key.to_sym]
      end

      def filename_for(book)
        id = value_for(book, :id, 'id', 'book').to_s
        title = value_for(book, :title, 'title', 'book').to_s
        slug = title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        slug = "book-#{id}" if slug.empty?
        "#{slug}-#{id}.epub"
      end

      def value_for(book, key_sym, key_str, default)
        return book[key_sym] if book.respond_to?(:key?) && book.key?(key_sym)
        return book[key_str] if book.respond_to?(:key?) && book.key?(key_str)

        default
      end
    end
  end
end
