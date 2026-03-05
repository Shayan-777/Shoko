# frozen_string_literal: true

require 'fileutils'

module Shoko
  module Adapters
    module Storage
      # Persistence helpers for writing cache payloads + pointer metadata.
      class EpubCache
        private

        def persist_payload(book_data, layouts_hash:)
          ensure_sha!
          generated_at = Time.now.utc

          success = @cache_store.write_payload(
            **payload_write_params(book_data, layouts_hash, generated_at)
          )
          return nil unless success

          metadata = pointer_metadata_for_write(generated_at, engine: cache_engine)
          write_pointer_metadata(metadata)
          metadata
        end

        def payload_write_params(book_data, layouts_hash, generated_at)
          serialized = Serializer.serialize(book_data, json: false)
          layouts_serialized = Serializer.serialize_layouts(layouts_hash)

          {
            sha: @source_sha,
            source_path: @source_path,
            source_mtime: safe_mtime(@source_path),
            generated_at: generated_at,
            serialized_book: serialized[:book],
            serialized_chapters: serialized[:chapters],
            serialized_resources: serialized[:resources],
            serialized_layouts: layouts_serialized,
          }
        end

        def write_pointer_metadata(metadata)
          @pointer_manager ||= CachePointerManager.new(@cache_path)
          @pointer_manager.write(metadata)
          @pointer_metadata = metadata
          @source_type = :cache_pointer
        end

        def pointer_metadata_for_write(generated_at, engine:)
          pointer_metadata(
            sha: @source_sha,
            source_path: @source_path,
            generated_at: generated_at.iso8601,
            engine: engine
          )
        end

        def pointer_metadata(sha:, source_path:, generated_at:, engine:)
          {
            'format' => CachePointerManager::POINTER_FORMAT,
            'version' => CachePointerManager::POINTER_VERSION,
            'sha256' => sha,
            'source_path' => source_path,
            'generated_at' => generated_at,
            'engine' => engine,
          }
        end

        def ensure_pointer_from_metadata(record)
          return unless record

          ensure_sha!
          pointer_metadata = pointer_metadata_for_record(record)
          return if pointer_current?(pointer_metadata['sha256'])

          write_pointer_metadata(pointer_metadata)
        end

        def pointer_metadata_for_record(record)
          record_engine = Serializer.value_for(record, :engine) || cache_engine
          pointer_metadata(
            sha: Serializer.value_for(record, :source_sha),
            source_path: Serializer.value_for(record, :source_path),
            generated_at: pointer_generated_at(record),
            engine: record_engine
          )
        end

        def pointer_generated_at(record)
          raw = Serializer.value_for(record, :generated_at)
          time = Serializer.coerce_time(raw)
          (time || Time.now.utc).iso8601
        end

        def pointer_current?(sha)
          current = @pointer_manager&.read
          current && current['sha256'] == sha
        end

        def cache_engine
          engine = @cache_store.engine
          engine || JsonCacheStore::ENGINE
        rescue Shoko::Error
          JsonCacheStore::ENGINE
        end

        def payload_matches_source?(payload, strict:)
          return true if cache_file? && !payload.source_path

          ensure_sha!
          return false unless payload.source_sha256 == @source_sha

          mtime_matches?(payload, strict: strict)
        end

        def mtime_matches?(payload, strict:)
          source_mtime = safe_mtime(@source_path)
          payload_mtime = payload.source_mtime
          return true unless source_mtime && payload_mtime

          tolerance = strict ? 1e-3 : 1.0
          (source_mtime.to_f - payload_mtime.to_f).abs <= tolerance
        end

        def safe_mtime(path)
          File.mtime(path)&.utc
        end
      end
    end
  end
end
