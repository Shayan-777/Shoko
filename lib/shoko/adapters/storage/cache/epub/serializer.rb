# frozen_string_literal: true

require 'json'

require 'shoko/shared/hash_normalizer'
require 'shoko/shared/text_sanitizer'

module Shoko
  module Adapters
    module Storage
      class EpubCache
        # Serializes cache payloads for JsonCacheStore and deserializes them
        # back into domain models.
        module Serializer
          module_function

          # --- Serialization ---

          def serialize(book_data, json: false)
            {
              book: serialize_book(book_data, json: json),
              chapters: serialize_chapters(book_data.chapters, json: json),
              resources: serialize_resources(book_data.resources),
            }
          end

          def serialize_layouts(layouts_hash)
            return {} unless layouts_hash.is_a?(Hash)

            layouts_hash.transform_keys(&:to_s)
          end

          def serialize_book(book, json: true)
            book_core_fields(book, json).merge(serialized_book_storage_fields(book, json))
          end

          def serialize_chapters(chapters, json: true)
            Array(chapters).each_with_index.map do |chapter, idx|
              metadata = chapter.metadata || {}
              {
                position: idx,
                number: chapter.number,
                title: chapter.title,
                metadata_json: json_field(metadata, json),
                raw_content: chapter.raw_content,
              }
            end
          end

          def serialize_resources(resources)
            return [] unless resources

            resources.map do |path, data|
              bytes = String(data).dup
              bytes.force_encoding(Encoding::BINARY)
              { path: path.to_s, data: bytes }
            end
          end

          def serialize_toc_entry(entry)
            {
              title: value_for(entry, :title),
              href: value_for(entry, :href),
              level: value_for(entry, :level),
              chapter_index: value_for(entry, :chapter_index),
              navigable: value_for(entry, :navigable),
            }
          end

          def json_field(value, json)
            json ? JSON.generate(value) : value
          end
          private_class_method :json_field

          def serialized_toc(book)
            Array(book.toc_entries).map { |entry| serialize_toc_entry(entry) }
          end
          private_class_method :serialized_toc

          def book_core_fields(book, json)
            {
              payload_version: CACHE_VERSION,
              cache_version: CACHE_VERSION,
              title: book.title,
              language: book.language,
              authors_json: json_field(Array(book.authors), json),
              metadata_json: json_field(book.metadata || {}, json),
              toc_json: json_field(serialized_toc(book), json),
            }
          end
          private_class_method :book_core_fields

          def serialized_book_storage_fields(book, json)
            {
              format_data_json: json_field(book.format_data || {}, json),
            }
          end
          private_class_method :serialized_book_storage_fields

          # --- Deserialization ---

          def build_payload_from_store(raw_payload, cache_root:, book_sha:)
            metadata = raw_payload.metadata_row || {}
            book = deserialize_book(
              metadata,
              raw_payload.chapters,
              raw_payload.resources,
              cache_root: cache_root,
              book_sha: book_sha
            )
            CachePayload.new(**cache_payload_attributes(metadata, raw_payload, book_sha: book_sha, book: book))
          end

          def deserialize_book(book_row, chapter_rows, resource_rows, cache_root:, book_sha:)
            expected_sha = book_sha.to_s
            validate_payload_sha!(book_row, cache_root, expected_sha)
            generation = chapters_generation!(book_row, cache_root)
            json_fields = parse_book_json_fields(book_row)

            chapters = deserialize_chapters(
              chapter_rows,
              cache_root: cache_root,
              book_sha: expected_sha,
              generation: generation
            )
            resources = deserialize_resources(resource_rows)
            fields = book_display_fields(book_row, json_fields)
            fields.merge!(book_navigation_fields(book_row, json_fields))
            fields.merge!(deserialized_book_storage_fields(json_fields, chapters, resources, generation))
            Shoko::Core::Models::BookData.new(**fields)
          end

          def cache_payload_attributes(metadata, raw_payload, book_sha:, book:)
            {
              version: value_for(metadata, :cache_version) || CACHE_VERSION,
              source_sha256: book_sha.to_s,
              source_path: value_for(metadata, :source_path),
              source_mtime: coerce_time(value_for(metadata, :source_mtime)),
              generated_at: coerce_time(value_for(metadata, :generated_at)),
              book: book,
              layouts: normalize_layouts(raw_payload.layouts),
            }
          end
          private_class_method :cache_payload_attributes

          def deserialize_chapters(rows, cache_root:, book_sha:, generation:)
            Array(rows).map do |row|
              idx = chapter_index(row)
              Shoko::Core::Models::Chapter.new(
                number: value_for(row, :number),
                title: sanitize_display(value_for(row, :title)),
                lines: [],
                metadata: chapter_metadata(row),
                blocks: nil,
                raw_content: chapter_raw_content(cache_root, book_sha, generation, idx)
              )
            end
          end

          def deserialize_toc(json)
            data = json.is_a?(String) ? JSON.parse(json || '[]') : json
            Array(data).map do |entry|
              Shoko::Core::Models::TOCEntry.new(
                title: sanitize_display(value_for(entry, :title)),
                href: sanitize_display(value_for(entry, :href)),
                level: value_for(entry, :level),
                chapter_index: value_for(entry, :chapter_index),
                navigable: toc_navigable?(entry)
              )
            end
          end

          def deserialize_resources(rows)
            Array(rows).each_with_object({}) do |row, acc|
              data = value_for(row, :data).to_s.dup
              data.force_encoding(Encoding::BINARY)
              path = value_for(row, :path)
              acc[path] = data if path
            end
          end

          def normalize_layouts(raw_layouts)
            return {} unless raw_layouts

            raw_layouts.is_a?(Hash) ? normalize_layouts_hash(raw_layouts) : normalize_layouts_rows(raw_layouts)
          end

          def normalize_layout_payload(payload)
            return nil unless payload

            payload.is_a?(String) ? JSON.parse(payload) : payload
          end

          def validate_payload_sha!(book_row, cache_root, expected_sha)
            declared_sha = value_for(book_row, :source_sha).to_s
            return if declared_sha == expected_sha

            raise Shoko::CacheLoadError.new(cache_root, 'sha mismatch in payload')
          end
          private_class_method :validate_payload_sha!

          def chapters_generation!(book_row, cache_root)
            generation = value_for(book_row, :chapters_generation).to_s
            return generation if generation.match?(JsonCacheStore::CHAPTERS_GENERATION_PATTERN)

            raise Shoko::CacheLoadError.new(cache_root, 'invalid chapters generation')
          end
          private_class_method :chapters_generation!

          def parse_book_json_fields(book_row)
            {
              authors: parse_json_array(value_for(book_row, :authors_json)),
              metadata: parse_json_hash(value_for(book_row, :metadata_json)),
              toc: parse_json_array(value_for(book_row, :toc_json)),
              format_data: parse_json_hash(value_for(book_row, :format_data_json)),
            }
          end
          private_class_method :parse_book_json_fields

          def book_display_fields(book_row, json_fields)
            authors = Array(json_fields[:authors]).map { |name| sanitize_display(name) }
            {
              title: sanitize_display(value_for(book_row, :title)),
              language: sanitize_display(value_for(book_row, :language)),
              authors: authors,
            }
          end
          private_class_method :book_display_fields

          def book_navigation_fields(_book_row, json_fields)
            {
              toc_entries: deserialize_toc(json_fields[:toc]),
            }
          end
          private_class_method :book_navigation_fields

          def deserialized_book_storage_fields(json_fields, chapters, resources, generation)
            {
              metadata: json_fields[:metadata] || {},
              chapters: chapters,
              resources: resources,
              chapters_generation: generation,
              format_data: normalize_format_data(json_fields[:format_data]),
            }
          end
          private_class_method :deserialized_book_storage_fields

          def normalize_format_data(format_data)
            normalized = parse_json_hash(format_data)
            normalized.is_a?(Hash) ? normalized : {}
          end
          private_class_method :normalize_format_data

          def chapter_index(row)
            pos = value_for(row, :position)
            Integer(pos)
          end
          private_class_method :chapter_index

          def chapter_metadata(row)
            metadata = value_for(row, :metadata_json)
            parse_json_hash(metadata)
          end
          private_class_method :chapter_metadata

          def chapter_raw_content(cache_root, book_sha, generation, idx)
            Shoko::Adapters::Storage::LazyFileString.new(
              chapter_raw_path(cache_root, book_sha, generation, idx),
              sanitizer: method(:sanitize_content)
            )
          end
          private_class_method :chapter_raw_content

          def chapter_raw_path(cache_root, book_sha, generation, idx)
            file = format("%0#{JsonCacheStore::CHAPTER_FILENAME_DIGITS}d.xhtml", idx)
            File.join(cache_root.to_s,
                      JsonCacheStore::CHAPTERS_DIRNAME,
                      book_sha,
                      generation,
                      JsonCacheStore::CHAPTERS_RAW_DIRNAME,
                      file)
          end
          private_class_method :chapter_raw_path

          def normalize_layouts_hash(layouts_hash)
            layouts_hash.each_with_object({}) do |(key, payload), acc|
              normalized = normalize_layout_payload(payload)
              acc[key.to_s] = normalized if normalized
            end
          end
          private_class_method :normalize_layouts_hash

          def normalize_layouts_rows(raw_layouts)
            Array(raw_layouts).each_with_object({}) do |row, acc|
              normalized = normalize_row_layout(row)
              acc[normalized[:key]] = normalized[:payload] if normalized
            end
          end
          private_class_method :normalize_layouts_rows

          def normalize_row_layout(row)
            key = value_for(row, :key)
            payload = value_for(row, :payload_json) || value_for(row, :payload)
            normalized = normalize_layout_payload(payload)
            return nil unless key && normalized

            { key: key.to_s, payload: normalized }
          end
          private_class_method :normalize_row_layout

          def toc_navigable?(entry)
            value_for(entry, :navigable) != false
          end
          private_class_method :toc_navigable?

          # --- Shared value coercion ---

          def coerce_time(raw)
            return raw if raw.is_a?(Time)
            return nil unless raw

            Time.at(raw.to_f).utc
          end

          def value_for(obj, key)
            case obj
            when Hash
              Shoko::Shared::HashNormalizer.symbolize_keys(obj)[key]
            when Struct
              obj[key]
            when Data
              Shoko::Shared::HashNormalizer.symbolize_keys(obj.to_h)[key]
            end
          end

          def sanitize_display(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
          end
          private_class_method :sanitize_display

          def sanitize_content(text)
            Shoko::Shared::TextSanitizer.sanitize(text.to_s, preserve_newlines: true, preserve_tabs: true)
          end
          private_class_method :sanitize_content

          def parse_json(raw, fallback_json:)
            return raw unless raw.is_a?(String)

            JSON.parse(raw.empty? ? fallback_json : raw)
          end
          private_class_method :parse_json

          def parse_json_array(raw)
            Array(parse_json(raw, fallback_json: '[]'))
          end
          private_class_method :parse_json_array

          def parse_json_hash(raw)
            parsed = parse_json(raw, fallback_json: '{}')
            parsed.is_a?(Hash) ? parsed : {}
          end
          private_class_method :parse_json_hash
        end
      end
    end
  end
end
