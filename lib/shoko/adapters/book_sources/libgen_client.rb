# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'
require_relative '../base_adapter'
require_relative '../../shared/errors'
require_relative '../../shared/version'

module Shoko
  module Adapters
    module BookSources
      # Client for the Libgen JSON API (`/json.php`) with mirror failover.
      #
      # The JSON API has no free-text search — it only accepts lookups by
      # id / identifier. Typed search therefore runs in two steps, both
      # against the same service:
      #
      #   1. `GET /index.php?req=…&curtab=e` — the site's full-text search,
      #      used ONLY as an ID finder (edition ids scraped in relevance
      #      order).
      #   2. `GET /json.php?object=e&ids=…` — full records hydrated through
      #      the JSON API, reordered to the search's relevance order, plus a
      #      second hydration of each edition's file rows (md5 / extension /
      #      filesize) so every result is downloadable.
      #
      # Downloads resolve through the site's real chain:
      # `ads.php?md5=…` → keyed `get.php` link → CDN, streamed to disk.
      class LibgenClient < Shoko::Adapters::BaseAdapter
        class Error < Shoko::Error; end

        # Mirrors are tried in order; the first that answers is promoted to
        # the front for subsequent requests.
        DEFAULT_MIRRORS = %w[
          https://libgen.gl
          https://libgen.bz
          https://libgen.vg
          https://libgen.la
        ].freeze

        # Edition fields verified against the live API (see libgen_api docs);
        # addkey 101 carries the edition language metadata.
        EDITION_FIELDS = 'title,author,year,publisher,libgen_topic,pages,type'
        FILE_FIELDS = 'md5,extension,filesize'
        LANGUAGE_ADDKEY = '101'

        EDITION_ID_PATTERN = /edition\.php\?id=(\d+)/
        DOWNLOAD_LINK_PATTERN = /get\.php\?md5=[a-fA-F0-9]{32}&key=[A-Za-z0-9]+/
        MD5_PATTERN = /\A[a-f0-9]{32}\z/

        PAGE_SIZE = 50
        MIN_QUERY_LENGTH = 3
        MAX_FETCH_REDIRECTS = 3
        MAX_DOWNLOAD_REDIRECTS = 6
        USER_AGENT = "Shoko/#{Shoko::VERSION}".freeze

        # Reader-friendliness order for picking one file per edition.
        FORMAT_PREFERENCE = %w[epub fb2 mobi azw3 azw pdf rtf].freeze

        TRANSPORT_ERRORS = [
          IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError
        ].freeze

        # @param base_url [String, nil] Optional single-service override
        #   (SHOKO_LIBGEN_URL); replaces the default mirror list entirely.
        def initialize(base_url: nil, mirrors: DEFAULT_MIRRORS, logger: nil, open_timeout: 5, read_timeout: 25)
          super(logger: logger)
          @mirrors = initial_mirrors(base_url, mirrors)
          raise ArgumentError, 'at least one mirror is required' if @mirrors.empty?

          @open_timeout = open_timeout
          @read_timeout = read_timeout
        end

        # Full-text search. `page_url` is an opaque page token produced by a
        # previous search (`next`/`previous`), mirror-independent.
        #
        # @return [Hash] { count:, next:, previous:, results: [book, …] }
        def search(query: nil, page_url: nil)
          request = page_url ? page_request(page_url) : first_page_request(query)
          ids = extract_edition_ids(fetch(index_path(request)))
          {
            count: ids.length,
            next: next_page_token(request, ids),
            previous: previous_page_token(request),
            results: hydrate_editions(ids),
          }
        end

        # Resolve a result's keyed download URL through `ads.php`.
        #
        # @param book [Hash] a search result carrying :md5
        # @return [String] absolute keyed get.php URL
        def resolve_download_url(book)
          md5 = value_for(book, :md5, 'md5', '').to_s.strip.downcase
          raise Error, "Invalid md5: #{md5.inspect}" unless md5.match?(MD5_PATTERN)

          link = fetch("/ads.php?md5=#{md5}")[DOWNLOAD_LINK_PATTERN]
          raise Error, 'No download link found (file may be unavailable)' unless link

          URI.join("#{preferred_mirror}/", link).to_s
        end

        # Stream `url` to `dest_path`, yielding (bytes_written, total_bytes).
        # Writes to an adjacent .part file and renames only after the body
        # completed, so an interrupted or cancelled download never leaves a
        # truncated file at the final path.
        def download(url, dest_path, &)
          stream_download(parse_http_uri(url), dest_path, MAX_DOWNLOAD_REDIRECTS, &)
          nil
        rescue *TRANSPORT_ERRORS => e
          raise translate_download_error(e, url, dest_path)
        end

        private

        def initial_mirrors(base_url, mirrors)
          override = base_url.to_s.strip.delete_suffix('/')
          return [override] unless override.empty?

          Array(mirrors).map { |mirror| mirror.to_s.delete_suffix('/') }.reject(&:empty?)
        end

        def preferred_mirror
          @mirrors.first
        end

        # ── search: request shaping ─────────────────────────────────────────

        def first_page_request(query)
          normalized = query.to_s.strip
          if normalized.length < MIN_QUERY_LENGTH
            raise Error, "Query must be at least #{MIN_QUERY_LENGTH} characters long"
          end

          { query: normalized, page: 1 }
        end

        # Page tokens are relative index.php URLs so they stay valid across
        # mirror failover.
        def page_request(page_url)
          params = URI.decode_www_form(parse_uri(page_url).query.to_s).to_h
          query = params['req'].to_s
          raise Error, "Invalid page token: #{page_url.inspect}" if query.empty?

          { query: query, page: [params['page'].to_i, 1].max }
        end

        def index_path(request)
          "/index.php?#{URI.encode_www_form(req: request[:query], curtab: 'e',
                                            res: PAGE_SIZE, page: request[:page])}"
        end

        def next_page_token(request, ids)
          return nil if ids.length < PAGE_SIZE

          page_token(request[:query], request[:page] + 1)
        end

        def previous_page_token(request)
          return nil if request[:page] <= 1

          page_token(request[:query], request[:page] - 1)
        end

        def page_token(query, page)
          "/index.php?#{URI.encode_www_form(req: query, page: page)}"
        end

        # Extract edition-detail ids from search HTML, deduped, in relevance
        # order.
        def extract_edition_ids(html)
          seen = {}
          html.to_s.scan(EDITION_ID_PATTERN).each_with_object([]) do |(id), acc|
            next if seen[id]

            seen[id] = true
            acc << id
          end.first(PAGE_SIZE)
        end

        # ── search: JSON hydration ──────────────────────────────────────────

        def hydrate_editions(ids)
          return [] if ids.empty?

          editions = records(object: 'e', ids: ids.join(','),
                             fields: EDITION_FIELDS, addkeys: LANGUAGE_ADDKEY)
          by_id = editions.to_h { |record| [record['_id'], record] }
          files = file_details_for(editions)
          # Search relevance order, not the API's id order.
          ids.filter_map { |id| build_book(by_id[id], files) }
        end

        # One hydration for every file row referenced by the page's editions.
        # File ids are stringified so numeric JSON values still match the
        # string-keyed record ids.
        def file_details_for(editions)
          file_ids = editions.flat_map { |record| file_entries(record).filter_map { |entry| file_id_for(entry) } }.uniq
          return {} if file_ids.empty?

          records(object: 'f', ids: file_ids.join(','), fields: FILE_FIELDS)
            .to_h { |record| [record['_id'], record] }
        end

        def file_id_for(entry)
          value = entry['f_id'].to_s
          value.empty? ? nil : value
        end

        def file_entries(record)
          sub = record['files']
          sub.is_a?(Hash) ? sub.values.grep(Hash) : []
        end

        # A result must be downloadable: editions without any usable file are
        # dropped rather than listed as dead rows.
        def build_book(edition, files)
          return nil unless edition

          file = preferred_file(edition, files)
          return nil unless file

          book_payload(edition, file)
        end

        def book_payload(edition, file)
          edition_payload(edition).merge(
            size: human_size(file['filesize']),
            extension: file['extension'].to_s.downcase,
            md5: file['md5'].to_s.downcase
          )
        end

        def edition_payload(edition)
          {
            id: edition['_id'].to_s,
            title: edition['title'].to_s,
            authors: split_authors(edition['author']),
            languages: languages_from(edition['add']),
            publisher: edition['publisher'].to_s,
            year: edition['year'].to_s,
            pages: edition['pages'].to_s,
          }
        end

        def preferred_file(edition, files)
          candidates = file_entries(edition).filter_map do |entry|
            detail = files[file_id_for(entry)] || {}
            md5 = (entry['md5'] || detail['md5']).to_s
            next nil if md5.strip.empty?

            { 'md5' => md5, 'extension' => detail['extension'], 'filesize' => detail['filesize'] }
          end
          candidates.min_by { |file| format_rank(file['extension']) }
        end

        def format_rank(extension)
          FORMAT_PREFERENCE.index(extension.to_s.downcase) || FORMAT_PREFERENCE.length
        end

        def split_authors(value)
          value.to_s.split(';').map(&:strip).reject(&:empty?)
        end

        # `add` metadata entries are { 'name_en' =>, 'value' =>, … }; the
        # language addkey is the only one requested.
        def languages_from(add)
          return [] unless add.is_a?(Hash)

          add.values.filter_map do |entry|
            next nil unless entry.is_a?(Hash)
            next nil unless entry['name_en'].to_s.match?(/language/i)

            value = entry['value'].to_s.strip
            value.empty? ? nil : value
          end
        end

        def human_size(bytes)
          n = bytes.to_i
          return '' if n <= 0

          units = %w[B KB MB GB TB]
          index = 0
          value = n.to_f
          while value >= 1024 && index < units.length - 1
            value /= 1024
            index += 1
          end
          format(value >= 100 || index.zero? ? '%d %s' : '%.1f %s', value, units[index])
        end

        # ── JSON API ────────────────────────────────────────────────────────

        # Query json.php and normalize into an ordered array of record
        # hashes, each carrying its id under '_id'. Subarrays (files/add)
        # are preserved.
        def records(params)
          json = query(params)
          case json
          when Hash
            json.filter_map { |id, record| record.is_a?(Hash) ? record.merge('_id' => id) : nil }
          when Array
            json.each_with_index.filter_map { |record, i| record.is_a?(Hash) ? record.merge('_id' => i.to_s) : nil }
          else
            []
          end
        end

        def query(params)
          clean = params.reject { |_, value| value.nil? || value.to_s.strip.empty? }
          json = parse_json(fetch("/json.php?#{URI.encode_www_form(clean)}"))
          raise Error, "API error: #{json['error']}" if json.is_a?(Hash) && json.key?('error') && json.size == 1

          json
        end

        def parse_json(body)
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise Error, "Invalid JSON from server: #{e.message}"
        end

        # ── transport with mirror failover ──────────────────────────────────

        # GET `path` from the first mirror that answers; a working mirror is
        # promoted to the front so later requests skip the dead ones.
        def fetch(path)
          errors = []
          @mirrors.each_with_index do |base, index|
            body = http_get(parse_uri("#{base}#{path}"), MAX_FETCH_REDIRECTS)
            @mirrors.unshift(@mirrors.delete_at(index)) if index.positive?
            return body
          rescue *TRANSPORT_ERRORS, URI::InvalidURIError, Error => e
            record_mirror_error(errors, base, e)
          end
          raise Error, "All mirrors failed: #{errors.join(' | ')}"
        end

        def record_mirror_error(errors, base, error)
          errors << "#{base}: #{error.message}"
          log_error('libgen_mirror_failed', mirror: base, error: error.message)
        end

        def http_get(uri, redirects)
          raise Error, 'Too many redirects' if redirects.negative?

          response = build_http(uri).request(request_for(uri))
          case response
          when Net::HTTPSuccess then (response.body || '').dup.force_encoding('UTF-8')
          when Net::HTTPRedirection then http_get(redirect_uri(uri, response), redirects - 1)
          else raise Error, "HTTP #{response.code}"
          end
        end

        def build_http(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          http
        end

        def request_for(uri)
          request = Net::HTTP::Get.new(uri)
          request['User-Agent'] = USER_AGENT
          request
        end

        def redirect_uri(uri, response)
          parse_uri(URI.join(uri.to_s, response['location'].to_s).to_s)
        end

        def parse_uri(value)
          URI.parse(value.to_s)
        rescue URI::InvalidURIError => e
          raise Error, "Invalid URL: #{e.message}"
        end

        def parse_http_uri(value)
          uri = parse_uri(value)
          raise Error, "Invalid URL: #{value}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          uri
        end

        # ── streaming download ──────────────────────────────────────────────

        def stream_download(uri, dest_path, redirects, &)
          raise Error, 'Too many redirects while downloading' if redirects.negative?

          build_http(uri).start do |http|
            http.request(request_for(uri)) do |response|
              handle_download_response(response, uri, dest_path, redirects, &)
            end
          end
        end

        def handle_download_response(response, uri, dest_path, redirects, &)
          case response
          when Net::HTTPSuccess
            write_body(response, dest_path, &)
          when Net::HTTPRedirection
            stream_download(redirect_uri(uri, response), dest_path, redirects - 1, &)
          else
            raise Error, "Download failed (HTTP #{response.code})"
          end
        end

        def write_body(response, dest_path)
          part_path = "#{dest_path}.part"
          total = response['content-length'].to_i
          written = 0
          File.open(part_path, 'wb') do |file|
            response.read_body do |chunk|
              file.write(chunk)
              written += chunk.bytesize
              yield(written, total) if block_given?
            end
          end
          File.rename(part_path, dest_path)
        ensure
          FileUtils.rm_f(part_path)
        end

        def translate_download_error(error, url, dest_path)
          log_error('libgen_download_failed', error: error.message, url: url.to_s, dest_path: dest_path)
          Error.new(error.message)
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
