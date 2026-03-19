# frozen_string_literal: true

require 'cgi'
require 'uri'
require_relative '../base_adapter'
require_relative '../../shared/errors'
require_relative 'libgen_client/html_parsing'
require_relative 'libgen_client/transport'

module Shoko
  module Adapters
    module BookSources
      # HTML client for Libgen-compatible search + download flows.
      class LibgenClient < Shoko::Adapters::BaseAdapter
        class Error < Shoko::Error; end

        DEFAULT_BASE_URL = 'https://libgen.bz'
        DEFAULT_COLUMNS = %w[t a s y p i].freeze
        DEFAULT_OBJECTS = %w[f e s a p w].freeze
        DEFAULT_TOPICS = %w[l].freeze
        DEFAULT_PAGE_SIZE = 100
        MAX_MIRRORS = 4
        USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        include HtmlParsing
        include Transport

        def initialize(base_url: DEFAULT_BASE_URL, logger: nil, open_timeout: 5, read_timeout: 15)
          super(logger: logger)
          @base_url = normalize_base_url(base_url)
          @open_timeout = open_timeout
          @read_timeout = read_timeout
        end

        def search(query:, page_url: nil)
          search_query = query.to_s.strip
          raise Error, 'Query must be at least 3 characters long' if search_query.length < 3

          uri = page_url ? normalize_uri(page_url, base: @base_url) : build_query_uri(search_query)
          books = parse_books(request_body(uri))
          {
            count: books.length,
            next: nil,
            previous: nil,
            results: books,
          }
        rescue URI::InvalidURIError, IOError, SystemCallError, SocketError, Timeout::Error => e
          log_error('libgen_search_failed', error: e.message, query: search_query, page_url: page_url.to_s)
          raise Error, e.message
        end

        def resolve_download_url(book)
          candidates = download_candidates_for(book)
          raise Error, 'No mirrors available for this result' if candidates.empty?

          resolve_candidate_download_url(candidates)
        rescue URI::InvalidURIError, IOError, SystemCallError, SocketError, Timeout::Error => e
          log_error('libgen_resolve_download_failed', error: e.message)
          raise Error, e.message
        end

        def download(url, dest_path)
          uri = normalize_uri(url, base: @base_url)
          request_download(uri, dest_path) { |done, total| yield(done, total) if block_given? }
        rescue URI::InvalidURIError, IOError, SystemCallError, SocketError, Timeout::Error => e
          log_error('libgen_download_failed', error: e.message, url: url.to_s, dest_path: dest_path)
          raise Error, e.message
        end

        private

        def normalize_base_url(value)
          uri = normalize_uri(value || DEFAULT_BASE_URL, base: DEFAULT_BASE_URL)
          uri.to_s.delete_suffix('/')
        end

        def build_query_uri(query)
          uri = URI.parse("#{@base_url}/index.php")
          uri.query = URI.encode_www_form(build_query_params(query))
          uri
        end

        def build_query_params(query)
          pairs = []
          pairs << ['req', query]
          DEFAULT_COLUMNS.each { |column| pairs << ['columns[]', column] }
          DEFAULT_OBJECTS.each { |object| pairs << ['objects[]', object] }
          DEFAULT_TOPICS.each { |topic| pairs << ['topics[]', topic] }
          pairs << ['res', DEFAULT_PAGE_SIZE.to_s]
          pairs << %w[filesuns all]
          pairs
        end

        def download_candidates_for(book)
          mirrors = Array(value_for(book, :mirrors, 'mirrors', [])).filter_map do |mirror|
            href = mirror.to_s.strip
            href.empty? ? nil : href
          end
          file_page = value_for(book, :file_page_url, 'file_page_url', nil).to_s.strip
          file_page.empty? ? mirrors : mirrors + [file_page]
        end

        def resolve_candidate_download_url(candidates)
          last_error = nil

          candidates.each do |candidate|
            return resolved_candidate_download_url(candidate)
          rescue Error => e
            last_error = e
          end

          raise(last_error || Error.new('No download links found on mirror page'))
        end

        def resolved_candidate_download_url(candidate)
          normalized = normalize_uri(candidate, base: @base_url)
          return normalized.to_s if direct_download_href?(normalized.to_s)

          html = request_body(normalized)
          href = extract_download_href(html)
          normalize_uri(href, base: normalized).to_s if href
        end

        def value_for(book, key_sym, key_str, default)
          return default unless book.is_a?(Hash)
          return book[key_sym] if book.key?(key_sym)
          return book[key_str] if book.key?(key_str)

          default
        end
      end
    end
  end
end
