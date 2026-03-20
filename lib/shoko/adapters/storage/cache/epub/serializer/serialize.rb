# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class EpubCache
        # Serialization helpers for persisting cache payloads.
        module Serializer
          module_function

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
            book_core_fields(book, json).merge(book_container_fields(book, json))
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
              opf_path: book.opf_path,
              spine_json: json_field(Array(book.spine), json),
              chapter_hrefs_json: json_field(Array(book.chapter_hrefs), json),
              toc_json: json_field(serialized_toc(book), json),
            }
          end
          private_class_method :book_core_fields

          def book_container_fields(book, json)
            {
              container_path: book.container_path,
              container_xml: book.container_xml.to_s,
              format_data_json: json_field(book.format_data || {}, json),
            }
          end
          private_class_method :book_container_fields
        end
      end
    end
  end
end
