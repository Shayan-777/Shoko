# frozen_string_literal: true

require 'fileutils'
require_relative '../base_adapter'
require_relative '../../shared/download_source_policy'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module BookSources
      # Coordinates remote catalog search + download to the local library.
      class DownloadService < Shoko::Adapters::BaseAdapter
        class DownloadError < Shoko::Error; end
        # Remote catalogs supply the id/extension that become path components.
        # Cap the extension so a hostile value can't bloat the filename.
        MAX_EXTENSION_LENGTH = 10
        EPUB_FORMAT_PREFERENCES = [
          ->(key) { key.start_with?('application/epub+zip') },
          ->(key) { key.include?('application/epub') },
          ->(key) { key.include?('epub') },
        ].freeze

        # @param gutendex_client [Object] Client for Gutendex API
        # @param libgen_client [Object] Client for Libgen-compatible HTML search
        # @param logger [Object, nil] Optional logger
        def initialize(gutendex_client:, libgen_client:, downloads_root: nil, logger: nil)
          super(logger: logger)
          @gutendex_client = gutendex_client
          @libgen_client = libgen_client
          @downloads_root = downloads_root
        end

        def search(query:, source:, page_url: nil)
          source_id = normalize_source(source)
          payload = client_for(source_id).search(query: query, page_url: page_url)
          {
            count: payload_value(payload, :count, 'count', 0).to_i,
            next: payload_value(payload, :next, 'next', nil),
            previous: payload_value(payload, :previous, 'previous', nil),
            books: normalize_books(payload_value(payload, :results, 'results', []), source: source_id),
          }
        end

        def download(book, source: nil)
          normalized_book = normalize_book_payload(book)
          source_id = normalize_source(source || value_for(normalized_book, :source, 'source', nil))
          url = pick_download_url(normalized_book, source: source_id)
          extension = filename_extension_for(normalized_book, source: source_id)
          raise DownloadError, missing_download_message(source_id) unless url

          dest_dir = downloads_root
          FileUtils.mkdir_p(dest_dir)
          dest_path = File.join(dest_dir, filename_for(normalized_book, extension: extension))
          ensure_within_downloads_root!(dest_dir, dest_path)
          return { path: dest_path, existing: true } if File.exist?(dest_path)

          client_for(source_id).download(url, dest_path) { |done, total| yield(done, total) if block_given? }
          { path: dest_path, existing: false }
        end

        private

        def downloads_root
          unless @downloads_root
            raise Shoko::ConfigurationError, 'DownloadService requires downloads_root: to be provided'
          end

          @downloads_root
        end

        def client_for(source)
          case normalize_source(source)
          when :gutendex
            @gutendex_client
          when :libgen
            @libgen_client
          else
            raise DownloadError, "Unsupported download source: #{source.inspect}"
          end
        end

        def normalize_books(items, source:)
          Array(items).map do |raw|
            normalize_book(raw, source: source)
          end
        end

        def normalize_book(raw, source:)
          case source
          when :gutendex
            normalize_gutendex_book(raw)
          when :libgen
            normalize_libgen_book(raw)
          else
            raise DownloadError, "Unsupported download source: #{source.inspect}"
          end
        end

        def pick_download_url(book, source:)
          case source
          when :gutendex
            pick_gutendex_download_url(book)
          when :libgen
            @libgen_client.resolve_download_url(book)
          else
            raise DownloadError, "Unsupported download source: #{source.inspect}"
          end
        end

        def pick_gutendex_download_url(book)
          formats = value_for(book, :formats, 'formats', {})
          return nil unless formats.is_a?(Hash)

          epub_key = preferred_epub_key(formats)
          return nil unless epub_key

          formats[epub_key] || formats[epub_key.to_sym]
        end

        def filename_for(book, extension:)
          id = sanitize_path_component(raw_id(book))
          title = value_for(book, :title, 'title', 'book').to_s
          slug = title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
          slug = "book-#{id}" if slug.empty?
          file_extension = normalize_extension(extension)
          "#{slug}-#{id}.#{file_extension}"
        end

        def raw_id(book)
          id = value_for(book, :id, 'id', '').to_s.strip
          id = value_for(book, :md5, 'md5', '').to_s.strip if id.empty?
          id
        end

        # Remote-supplied ids/titles become a single path segment, so strip
        # everything that isn't filename-safe (collapsing runs to a single dash)
        # and never let the result be empty or carry a path separator.
        def sanitize_path_component(value)
          cleaned = value.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
          cleaned.empty? ? 'book' : cleaned
        end

        # The resolved destination must stay directly inside the downloads root;
        # a sanitized filename can't escape, but verify defensively so any future
        # regression fails loudly instead of writing outside the library.
        def ensure_within_downloads_root!(dest_dir, dest_path)
          root = File.expand_path(dest_dir)
          prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
          return if File.expand_path(dest_path).start_with?(prefix)

          raise DownloadError, 'Resolved download path escapes the downloads directory'
        end

        def filename_extension_for(book, source:)
          extension = case source
                      when :gutendex
                        'epub'
                      when :libgen
                        value_for(book, :extension, 'extension', 'epub')
                      end

          extension || 'epub'
        end

        def normalize_gutendex_book(raw)
          {
            source: :gutendex,
            id: payload_value(raw, :id, 'id', nil),
            title: payload_value(raw, :title, 'title', nil),
            authors: normalized_gutendex_authors(raw),
            languages: normalized_payload_array(raw, :languages, 'languages'),
            download_count: payload_value(raw, :download_count, 'download_count', 0),
            formats: payload_value(raw, :formats, 'formats', {}),
          }
        end

        def normalize_libgen_book(raw)
          {
            source: :libgen,
            id: payload_value(raw, :id, 'id', ''),
            title: payload_value(raw, :title, 'title', ''),
            authors: normalized_payload_array(raw, :authors, 'authors'),
            languages: normalized_payload_array(raw, :languages, 'languages'),
            publisher: payload_value(raw, :publisher, 'publisher', ''),
            year: payload_value(raw, :year, 'year', ''),
            pages: payload_value(raw, :pages, 'pages', ''),
            size: payload_value(raw, :size, 'size', ''),
            extension: payload_value(raw, :extension, 'extension', ''),
            md5: payload_value(raw, :md5, 'md5', ''),
          }
        end

        def normalized_gutendex_authors(raw)
          Array(payload_value(raw, :authors, 'authors', [])).filter_map do |author|
            author.is_a?(Hash) ? payload_value(author, :name, 'name', nil) : author.to_s
          end
        end

        def normalized_payload_array(payload, key_sym, key_str)
          Array(payload_value(payload, key_sym, key_str, [])).map(&:to_s)
        end

        def preferred_epub_key(formats)
          keys = formats.keys.map(&:to_s)
          EPUB_FORMAT_PREFERENCES.each do |matcher|
            candidate = keys.find { |key| matcher.call(key) }
            return candidate if candidate
          end

          nil
        end

        def normalize_extension(extension)
          value = extension.to_s.strip.downcase.gsub(/[^a-z0-9]/, '')[0, MAX_EXTENSION_LENGTH].to_s
          value.empty? ? 'epub' : value
        end

        def missing_download_message(source)
          source == :gutendex ? 'No EPUB format available' : 'No download URL available'
        end

        def normalize_source(source)
          return Shoko::Shared::DownloadSourcePolicy.default_id if source.nil?

          normalized = Shoko::Shared::DownloadSourcePolicy.normalize(source)
          raise DownloadError, "Unsupported download source: #{source.inspect}" unless normalized

          normalized
        end

        def normalize_book_payload(book)
          raise DownloadError, "download payload must be a Hash, got #{book.class}" unless book.is_a?(Hash)

          book.transform_keys do |key|
            key.is_a?(String) ? key.to_sym : key
          end
        end

        def payload_value(payload, key_sym, key_str, default)
          return default unless payload.is_a?(Hash)
          return payload[key_sym] if payload.key?(key_sym)
          return payload[key_str] if payload.key?(key_str)

          default
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
