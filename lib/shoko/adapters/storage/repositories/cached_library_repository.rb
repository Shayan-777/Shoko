# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../cache_paths'
require_relative '../json_cache_store'
require_relative '../cache_pointer_manager'
require_relative '../epub_cache'
require_relative '../../../shared/text_sanitizer'
require_relative '../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Storage
      module Repositories
        # Provides read-only access to cached library metadata on disk.
        class CachedLibraryRepository
          def initialize(cache_root:, store:, runtime_config:, manifest_store:, cache_class:, pointer_manager_class:)
            @cache_root = cache_root
            @runtime_config = runtime_config
            @cache_store = store
            @manifest_store = manifest_store
            @cache_class = cache_class
            @pointer_manager_class = pointer_manager_class
          end

          def list_entries
            rows = fetch_manifest_rows
            rows = fetch_rows if rows.empty?
            return [] if rows.empty?

            rows.filter_map { |row| build_entry_from_row(row) }
          end

          private

          def fetch_rows
            @cache_store.list_books
          end

          def fetch_manifest_rows
            @manifest_store.manifest_rows(@cache_root, runtime_config: @runtime_config)
          end

          def build_entry_from_row(row)
            normalized = normalize_row(row)
            sha = normalized[:source_sha]
            pointer_path = @cache_class.cache_path_for_sha(sha, cache_root: @cache_root)
            return nil unless pointer_path

            ensure_pointer_file(normalized, pointer_path)

            metadata = parse_json_object(normalized[:metadata_json])
            authors = parse_json_array(normalized[:authors_json]).map { |name| sanitize_display(name.to_s) }

            source_path = normalized[:source_path].to_s
            {
              title: sanitize_display(present_or_default(normalized[:title], 'Unknown')),
              authors: authors.join(', '),
              year: extract_year(metadata),
              size_bytes: (normalized[:cache_size_bytes] || safe_file_size(pointer_path)).to_i,
              open_path: pointer_path,
              book_path: source_path,
              epub_path: source_path,
            }
          end

          def ensure_pointer_file(row, path)
            return path if File.exist?(path) || row[:source_sha].to_s.empty?

            generated_at = begin
              raw = row[:generated_at]
              raw ? Time.at(raw.to_f).utc.iso8601 : Time.now.utc.iso8601
            rescue Shoko::Error
              Time.now.utc.iso8601
            end

            metadata = {
              'format' => Adapters::Storage::CachePointerManager::POINTER_FORMAT,
              'version' => Adapters::Storage::CachePointerManager::POINTER_VERSION,
              'sha256' => row[:source_sha],
              'source_path' => row[:source_path],
              'generated_at' => generated_at,
              'engine' => Adapters::Storage::JsonCacheStore::ENGINE,
            }

            @pointer_manager_class.new(path).write(metadata)
            path
          end

          def parse_json_object(value)
            return {} unless value
            return Shoko::Shared::HashNormalizer.deep_symbolize(value) if value.is_a?(Hash)

            parsed = JSON.parse(value)
            parsed.is_a?(Hash) ? Shoko::Shared::HashNormalizer.deep_symbolize(parsed) : {}
          end

          def parse_json_array(value)
            return [] unless value
            return value if value.is_a?(Array)

            parsed = JSON.parse(value)
            parsed.is_a?(Array) ? parsed : []
          end

          def extract_year(metadata)
            return '' unless metadata.is_a?(Hash)

            year = metadata[:year]
            year ? year.to_s : ''
          end

          def normalize_row(row)
            Shoko::Shared::HashNormalizer.symbolize_keys(row) || {}
          end

          def present_or_default(value, fallback)
            str = value.to_s.strip
            str.empty? ? fallback : value
          end

          def safe_file_size(path)
            File.size(path)
          end

          def sanitize_display(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                             preserve_tabs: false)
          rescue Shoko::Error
            text.to_s
          end
        end
      end
    end
  end
end
