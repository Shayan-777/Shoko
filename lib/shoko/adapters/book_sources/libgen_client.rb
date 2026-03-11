# frozen_string_literal: true

require 'cgi'
require 'uri'
require_relative '../base_adapter'
require_relative '../../shared/errors'

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
        USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'.freeze

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
        rescue URI::InvalidURIError, IOError, SystemCallError, SocketError, Timeout::Error, EOFError => e
          log_error('libgen_search_failed', error: e.message, query: search_query, page_url: page_url.to_s)
          raise Error, e.message
        end

        def resolve_download_url(book)
          candidates = download_candidates_for(book)
          raise Error, 'No mirrors available for this result' if candidates.empty?

          last_error = nil
          candidates.each do |candidate|
            begin
              normalized = normalize_uri(candidate, base: @base_url)
              return normalized.to_s if direct_download_href?(normalized.to_s)

              html = request_body(normalized)
              href = extract_download_href(html)
              return normalize_uri(href, base: normalized).to_s if href
            rescue Error => e
              last_error = e
            end
          end

          raise(last_error || Error.new('No download links found on mirror page'))
        rescue URI::InvalidURIError, IOError, SystemCallError, SocketError, Timeout::Error, EOFError => e
          log_error('libgen_resolve_download_failed', error: e.message)
          raise Error, e.message
        end

        def download(url, dest_path)
          uri = normalize_uri(url, base: @base_url)
          request_download(uri, dest_path) { |done, total| yield(done, total) if block_given? }
        rescue URI::InvalidURIError, IOError, SystemCallError, SocketError, Timeout::Error, EOFError => e
          log_error('libgen_download_failed', error: e.message, url: url.to_s, dest_path: dest_path)
          raise Error, e.message
        end

        private

        def normalize_base_url(value)
          uri = normalize_uri(value || DEFAULT_BASE_URL, base: DEFAULT_BASE_URL)
          uri.to_s.sub(%r{/\z}, '')
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
          pairs << ['filesuns', 'all']
          pairs
        end

        def parse_books(html)
          table = extract_table(html)
          return [] unless table

          extract_rows(table).filter_map { |row| parse_row(row) }
        end

        def extract_table(html)
          match = html.to_s.match(/<table\b[^>]*\bid\s*=\s*["']tablelibgen["'][^>]*>(.*?)<\/table>/im)
          match && match[1]
        end

        def extract_rows(table_html)
          source = extract_body(table_html) || table_html.to_s
          source.scan(/<tr\b[^>]*>(.*?)<\/tr>/im).flatten
        end

        def extract_body(table_html)
          match = table_html.to_s.match(/<tbody\b[^>]*>(.*?)<\/tbody>/im)
          match && match[1]
        end

        def parse_row(row_html)
          cells = row_html.to_s.scan(/<t[dh]\b[^>]*>(.*?)<\/t[dh]>/im).flatten
          return nil if cells.length < 9

          title_link = extract_primary_title_link(cells[0])
          return nil if title_link.nil?

          title = title_link[:text]
          return nil if title.empty?

          mirrors = extract_links(cells[8]).first(MAX_MIRRORS).map { |link| absolute_url(link[:href]) }.compact
          file_page_url = absolute_url(extract_primary_href(cells[6]))
          md5 = extract_md5(mirrors.first)
          id = extract_id(title_link[:href])
          id = extract_id(file_page_url) if id.empty?
          id = md5 if id.empty?
          {
            id: id,
            title: title,
            authors: extract_people(cells[1]),
            languages: split_values(cells[4]),
            publisher: normalize_text(cells[2]),
            year: normalize_text(cells[3]),
            pages: normalize_text(cells[5]),
            size: normalize_text(extract_primary_link_text(cells[6])),
            extension: normalize_text(cells[7]).downcase,
            md5: md5,
            file_page_url: file_page_url,
            mirrors: mirrors,
          }
        end

        def extract_primary_title_link(cell_html)
          first_line = cell_html.to_s.split(/<br\s*\/?>/i, 2).first.to_s
          link = extract_links(first_line).find { |candidate| meaningful_title_link?(candidate) }
          link || extract_links(cell_html).find { |candidate| meaningful_title_link?(candidate) }
        end

        def meaningful_title_link?(candidate)
          return false unless candidate

          text = candidate[:text].to_s.strip
          href = candidate[:href].to_s
          return false if text.empty? || text == '↕'

          href.include?('edition.php') || href.include?('book/index.php') || href.include?('id=')
        end

        def extract_primary_link_text(cell_html)
          links = extract_links(cell_html)
          return links.first[:text] unless links.empty?

          cell_html
        end

        def extract_primary_href(cell_html)
          links = extract_links(cell_html)
          links.first && links.first[:href]
        end

        def split_values(cell_html)
          normalize_text(cell_html).split(/[,;]+/).map(&:strip).reject(&:empty?)
        end

        def extract_people(cell_html)
          links = extract_links(cell_html)
          values = if links.empty?
                     split_values(cell_html)
                   else
                     links.map { |link| link[:text].to_s.strip }.reject(&:empty?)
                   end
          values = [normalize_text(cell_html)] if values.empty?
          values.reject(&:empty?)
        end

        def extract_links(html)
          collect_anchor_fragments(html.to_s).filter_map do |attributes, body|
            href = extract_attribute(attributes, 'href')
            next nil if href.to_s.strip.empty?

            {
              href: href,
              text: normalize_text(body),
            }
          end
        end

        def collect_anchor_fragments(html)
          fragments = []
          position = 0
          while (anchor_start = html.index(/<a\b/i, position))
            tag_end = find_tag_end(html, anchor_start + 2)
            break unless tag_end

            close_start = html.index(%r{</a>}i, tag_end + 1)
            break unless close_start

            attributes = html[(anchor_start + 2)...tag_end]
            body = html[(tag_end + 1)...close_start]
            fragments << [attributes, body]
            position = close_start + 4
          end
          fragments
        end

        def find_tag_end(html, start_index)
          quote = nil
          index = start_index
          while index < html.length
            char = html[index]
            if quote
              quote = nil if char == quote
            elsif char == '"' || char == "'"
              quote = char
            elsif char == '>'
              return index
            end
            index += 1
          end

          nil
        end

        def extract_attribute(attributes, key)
          match = attributes.to_s.match(/\b#{Regexp.escape(key)}\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
          match&.captures&.compact&.first
        end

        def extract_id(href)
          query = URI.parse(absolute_url(href)).query
          query_value(query, 'id').to_s
        rescue URI::InvalidURIError
          ''
        end

        def extract_md5(url)
          return '' if url.to_s.strip.empty?

          query = URI.parse(url).query
          query_value(query, 'md5').to_s
        rescue URI::InvalidURIError
          ''
        end

        def absolute_url(href)
          return nil if href.to_s.strip.empty?

          normalize_uri(href, base: @base_url).to_s
        rescue URI::InvalidURIError
          nil
        end

        def extract_download_href(html)
          extract_links(html).each do |link|
            href = link[:href].to_s
            return href if direct_download_href?(href)
          end

          raise Error, 'No download links found on mirror page'
        end

        def direct_download_href?(href)
          href.match?(/(?:^|\/)(?:get|download|file\.php)\b/i) || href.include?('get=') || href.include?('download=')
        end

        def normalize_text(text)
          decoded = CGI.unescapeHTML(text.to_s.gsub(/<[^>]+>/, ' '))
          decoded.gsub(/\s+/, ' ').strip
        end

        def query_value(query, key)
          URI.decode_www_form(query.to_s).each do |pair_key, pair_value|
            return pair_value if pair_key == key
          end

          nil
        end

        def download_candidates_for(book)
          mirrors = Array(value_for(book, :mirrors, 'mirrors', [])).filter_map do |mirror|
            href = mirror.to_s.strip
            href.empty? ? nil : href
          end
          file_page = value_for(book, :file_page_url, 'file_page_url', nil).to_s.strip
          file_page.empty? ? mirrors : mirrors + [file_page]
        end

        def request_body(uri, limit = 2)
          response = request(uri)
          return response.body if response.is_a?(Net::HTTPSuccess)

          if response.is_a?(Net::HTTPRedirection) && limit.positive?
            redirect = resolve_redirect_uri(uri, response['location'])
            return request_body(redirect, limit - 1)
          end

          raise Error, "Request failed (#{response.code})"
        end

        def request_download(uri, dest_path, limit = 2)
          response = request(uri) do |http|
            http.request(Net::HTTP::Get.new(uri.request_uri, request_headers)) do |resp|
              if resp.is_a?(Net::HTTPSuccess)
                stream_response(resp, dest_path) { |done, total| yield(done, total) if block_given? }
              else
                resp
              end
            end
          end

          if response.is_a?(Net::HTTPRedirection) && limit.positive?
            redirect = resolve_redirect_uri(uri, response['location'])
            return request_download(redirect, dest_path, limit - 1) { |done, total| yield(done, total) if block_given? }
          end

          return response if response.is_a?(Net::HTTPSuccess)

          raise Error, "Download failed (#{response.code})"
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

        def request(uri)
          ensure_http_dependencies!
          normalized = normalize_uri(uri, base: @base_url)
          raise Error, "Invalid URL: #{normalized}" unless normalized.is_a?(URI::HTTP) || normalized.is_a?(URI::HTTPS)

          http = Net::HTTP.new(normalized.host, normalized.port)
          http.use_ssl = normalized.scheme == 'https'
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          if block_given?
            http.start { |client| yield(client) }
          else
            http.get(normalized.request_uri, request_headers)
          end
        rescue Error, IOError, SystemCallError, SocketError, Timeout::Error, EOFError => e
          log_error('libgen_request_failed', error: e.message, url: uri.to_s)
          raise Error, e.message
        end

        def request_headers
          { 'User-Agent' => USER_AGENT }
        end

        def normalize_uri(input, base: nil)
          uri = input.is_a?(URI) ? input : URI.parse(input.to_s)
          return uri if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          return URI.join(base.to_s, uri.to_s) if base

          if uri.scheme.nil? && uri.host.nil?
            candidate = uri.to_s
            return URI.parse("https:#{candidate}") if candidate.start_with?('//')
            return URI.parse("https://#{candidate}") if /\A[a-z0-9.-]+\.[a-z]{2,}/i.match?(candidate)
          end

          uri
        end

        def resolve_redirect_uri(base_uri, location)
          normalize_uri(location, base: base_uri)
        end

        def ensure_http_dependencies!
          return if defined?(Net::HTTP) && defined?(URI::DEFAULT_PARSER)

          require 'net/http'
          require 'uri'
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
