# frozen_string_literal: true

require 'digest'
require_relative '../archive/zip_reader'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Loads resources (typically images) from an EPUB on-demand and optionally
        # persists them as per-book blobs under the cache root.
        class EpubResourceLoader
          SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

          def initialize(
            cache_root: nil,
            file_writer: nil,
            logger: nil,
            runtime_config: nil,
            archive_reader: Shoko::Adapters::BookSources::Archive::ZipReader
          )
            raise Shoko::ConfigurationError, 'EpubResourceLoader requires cache_root: to be provided' unless cache_root

            @cache_root = cache_root
            @file_writer = file_writer
            @logger = logger
            @runtime_config = runtime_config
            @archive_reader = archive_reader
          end

          # Fetch an entry from the per-book blob cache or from the EPUB archive.
          #
          # @param book_sha [String,nil] 64-char hex digest identifying the book cache directory
          # @param epub_path [String] filesystem path to the EPUB
          # @param entry_path [String] path inside the EPUB zip
          # @param cache_key [String,nil] logical cache key (defaults to entry_path)
          # @return [String,nil] binary bytes
          def fetch(book_sha:, epub_path:, entry_path:, persist: true, cache_key: nil)
            return nil if entry_path.to_s.empty?

            normalized_sha = normalize_sha(book_sha)
            key = cache_lookup_key(cache_key, entry_path)
            return nil if key.empty?

            cached = cached_blob(normalized_sha, key)
            return cached if cached

            bytes = read_from_zip(epub_path, entry_path)
            return nil unless bytes

            persist_blob(normalized_sha, key, bytes) if persist
            bytes
          end

          def cache_entry(book_sha:, entry_path:, bytes:)
            normalized_sha = normalize_sha(book_sha)
            return nil unless normalized_sha
            return nil if entry_path.to_s.empty?

            write_blob(normalized_sha, entry_path, bytes)
          end

          def cached?(book_sha:, entry_path:)
            normalized_sha = normalize_sha(book_sha)
            return false unless normalized_sha
            return false if entry_path.to_s.empty?

            File.file?(blob_path(normalized_sha, entry_path))
          end

          # Resolve a resource href relative to a chapter (zip entry) path.
          #
          # @param chapter_entry_path [String] zip entry path of the chapter
          # @param href [String] href/src value from XHTML
          # @return [String,nil] normalized zip entry path
          def self.resolve_chapter_relative(chapter_entry_path, href)
            return nil unless chapter_entry_path && href

            core = href.to_s.split(/[?#]/, 2).first.to_s
            return nil if core.empty?
            return nil if core.match?(/\A[a-z][a-z0-9+.-]*:/i) # data:, http:, etc.

            normalized = if core.start_with?('/')
                           core.sub(%r{\A/+}, '')
                         else
                           base = File.dirname(chapter_entry_path.to_s)
                           File.expand_path(File.join('/', base, core), '/').sub(%r{^/}, '')
                         end

            normalized.empty? ? nil : normalized
          end

          private

          def cache_lookup_key(cache_key, entry_path)
            (cache_key || entry_path).to_s
          end

          def cached_blob(normalized_sha, key)
            return nil unless normalized_sha

            read_blob(normalized_sha, key)
          end

          def persist_blob(normalized_sha, key, bytes)
            return unless normalized_sha

            write_blob(normalized_sha, key, bytes)
          end

          def normalize_sha(sha)
            value = sha.to_s.strip
            return nil if value.empty?
            return nil unless SHA256_HEX_PATTERN.match?(value)

            value.downcase
          end

          def read_from_zip(epub_path, entry_path)
            return nil unless readable_zip_request?(epub_path, entry_path)

            @archive_reader.open(epub_path, runtime_config: @runtime_config) do |zip|
              read_zip_entry(zip, entry_path)
            end
          rescue Zip::Error => e
            log_read_error('EpubResourceLoader: zip read failed', epub_path, entry_path, e)
            nil
          rescue Shoko::Error => e
            log_read_error('EpubResourceLoader: read failed', epub_path, entry_path, e)
            nil
          end

          def readable_zip_request?(epub_path, entry_path)
            epub_path && File.file?(epub_path) && !entry_path.to_s.empty?
          end

          def log_read_error(message, epub_path, entry_path, error)
            @logger&.debug(message, path: epub_path.to_s, entry: entry_path.to_s, error: error.message)
          end

          def read_zip_entry(zip, entry_path)
            entry_name = entry_path.to_s
            return nil unless zip.find_entry(entry_name)

            data = zip.read(entry_name)
            data.force_encoding(Encoding::BINARY)
            data
          end

          def blob_path(book_sha, entry_path)
            key = Digest::SHA256.hexdigest(entry_path.to_s)
            File.join(@cache_root, 'resources', book_sha.to_s, "#{key}.bin")
          end

          def read_blob(book_sha, entry_path)
            path = blob_path(book_sha, entry_path)
            return nil unless File.file?(path)

            data = File.binread(path)
            data.force_encoding(Encoding::BINARY)
            data
          end

          def write_blob(book_sha, entry_path, bytes)
            return unless book_sha

            writer = @file_writer
            return unless writer

            path = blob_path(book_sha, entry_path)
            writer.write(path, bytes, binary: true)
            path
          end
        end
      end
    end
  end
end
