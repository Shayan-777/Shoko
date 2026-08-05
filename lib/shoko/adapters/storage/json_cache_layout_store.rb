# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'atomic_file_writer'
require 'shoko/shared/resilient_diagnostics'

module Shoko
  module Adapters
    module Storage
      # Owns the lifecycle and validation of cached pagination layouts.
      class JsonCacheLayoutStore
        SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i
        MAX_KEY_BYTES = 200
        KEY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

        def initialize(cache_root:, logger: nil)
          @cache_root = cache_root
          @logger = logger
        end

        def load(sha, key)
          file = layout_file(sha, key)
          return nil unless File.file?(file)

          JSON.parse(File.read(file))
        # resilient-boundary
        rescue StandardError => e
          record_layout_error('load failed', e, sha: sha.to_s, key: key.to_s)
        end

        def fetch(sha)
          dir = layouts_dir(sha)
          return {} unless Dir.exist?(dir)

          Dir.children(dir).each_with_object({}) do |entry, layouts|
            key = key_for_entry(entry)
            next unless key

            payload = read_payload(dir, entry, sha: sha, key: key)
            layouts[key] = payload if payload
          end
        # resilient-boundary
        rescue StandardError => e
          record_layout_error('fetch failed', e, sha: sha.to_s)
          {}
        end

        def mutate(sha)
          layouts = fetch(sha)
          yield layouts
          write(sha, layouts)
          true
        # resilient-boundary
        rescue StandardError => e
          record_layout_error('mutation failed', e, sha: sha.to_s)
          false
        end

        def write(sha, layouts)
          dir = layouts_dir(sha)
          FileUtils.mkdir_p(dir)
          existing = Dir.children(dir).select { |entry| entry.end_with?('.json') }
          written = Array(layouts).map do |key, payload|
            normalized_key = normalize_key!(key)
            filename = "#{normalized_key}.json"
            AtomicFileWriter.write(File.join(dir, filename), JSON.generate(payload))
            filename
          end
          (existing - written).each { |entry| FileUtils.rm_f(File.join(dir, entry)) }
          nil
        end

        def delete(sha)
          FileUtils.rm_rf(layouts_dir(sha))
        end

        private

        def layouts_dir(sha)
          File.join(@cache_root, 'layouts', normalize_sha!(sha))
        end

        def layout_file(sha, key)
          File.join(layouts_dir(sha), "#{normalize_key!(key)}.json")
        end

        def key_for_entry(entry)
          return nil unless entry.end_with?('.json')

          key = entry.delete_suffix('.json')
          normalize_key!(key)
        rescue ArgumentError
          nil
        end

        def read_payload(dir, entry, sha:, key:)
          JSON.parse(File.read(File.join(dir, entry)))
        # resilient-boundary
        rescue StandardError => e
          record_layout_error('parse failed', e, sha: sha.to_s, key: key.to_s)
        end

        def normalize_sha!(sha)
          value = sha.to_s.strip
          raise ArgumentError, 'sha is blank' if value.empty?
          raise ArgumentError, 'sha must be a 64-char hex digest' unless SHA256_HEX_PATTERN.match?(value)

          value.downcase
        end

        def normalize_key!(key)
          value = key.to_s
          raise ArgumentError, 'layout key is blank' if value.empty?
          raise ArgumentError, 'layout key too long' if value.bytesize > MAX_KEY_BYTES
          raise ArgumentError, 'layout key contains null byte' if value.include?("\0")
          raise ArgumentError, 'layout key contains path separator' if value.include?('/') || value.include?('\\')
          raise ArgumentError, 'layout key has invalid characters' unless KEY_PATTERN.match?(value)

          value
        end

        def record_layout_error(operation, error, **context)
          Shoko::Shared::ResilientDiagnostics.debug(
            @logger,
            "JsonCacheLayoutStore: #{operation}",
            **context,
            error_class: error.class.name,
            error: error.message
          )
          nil
        end
      end
    end
  end
end
