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
            {
              source: :gutendex,
              id: payload_value(raw, :id, 'id', nil),
              title: payload_value(raw, :title, 'title', nil),
              authors: Array(payload_value(raw, :authors, 'authors', [])).filter_map do |author|
                if author.is_a?(Hash)
                  payload_value(author, :name, 'name', nil)
                else
                  author.to_s
                end
              end,
              languages: Array(payload_value(raw, :languages, 'languages', [])).map(&:to_s),
              download_count: payload_value(raw, :download_count, 'download_count', 0),
              formats: payload_value(raw, :formats, 'formats', {}),
            }
          when :libgen
            {
              source: :libgen,
              id: payload_value(raw, :id, 'id', ''),
              title: payload_value(raw, :title, 'title', ''),
              authors: Array(payload_value(raw, :authors, 'authors', [])).map(&:to_s),
              languages: Array(payload_value(raw, :languages, 'languages', [])).map(&:to_s),
              publisher: payload_value(raw, :publisher, 'publisher', ''),
              year: payload_value(raw, :year, 'year', ''),
              pages: payload_value(raw, :pages, 'pages', ''),
              size: payload_value(raw, :size, 'size', ''),
              extension: payload_value(raw, :extension, 'extension', ''),
              md5: payload_value(raw, :md5, 'md5', ''),
              file_page_url: payload_value(raw, :file_page_url, 'file_page_url', ''),
              mirrors: Array(payload_value(raw, :mirrors, 'mirrors', [])),
            }
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

          keys = formats.keys.map(&:to_s)
          epub_key = keys.find { |k| k.start_with?('application/epub+zip') } ||
                     keys.find { |k| k.include?('application/epub') } ||
                     keys.find { |k| k.include?('epub') }
          return nil unless epub_key

          formats[epub_key] || formats[epub_key.to_sym]
        end

        def filename_for(book, extension:)
          id = value_for(book, :id, 'id', '').to_s.strip
          id = value_for(book, :md5, 'md5', 'book').to_s.strip if id.empty?
          id = 'book' if id.empty?
          title = value_for(book, :title, 'title', 'book').to_s
          slug = title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
          slug = "book-#{id}" if slug.empty?
          file_extension = normalize_extension(extension)
          "#{slug}-#{id}.#{file_extension}"
        end

        def filename_extension_for(book, source:)
          case source
          when :gutendex
            'epub'
          when :libgen
            value_for(book, :extension, 'extension', 'epub')
          else
            'epub'
          end
        end

        def normalize_extension(extension)
          value = extension.to_s.strip.downcase.sub(/\A\./, '')
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

          book.each_with_object({}) do |(key, value), normalized|
            normalized[key.is_a?(String) ? key.to_sym : key] = value
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
