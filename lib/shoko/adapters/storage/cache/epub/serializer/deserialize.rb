# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class EpubCache
        # Deserialization helpers for reading cache payloads from JsonCacheStore.
        module Serializer
          module_function

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
        end
      end
    end
  end
end
