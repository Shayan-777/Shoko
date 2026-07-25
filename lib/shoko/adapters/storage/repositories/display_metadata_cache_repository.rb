# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

require 'shoko/application/ports/outbound/display_metadata_cache'
require_relative '../atomic_file_writer'
require_relative '../cache_paths'
require 'shoko/shared/errors'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/display_metadata_fingerprint'

module Shoko
  module Adapters
    module Storage
      module Repositories
        # JSON-backed cache for lightweight display metadata used by Browse Library.
        class DisplayMetadataCacheRepository
          DisplayMetadataFingerprint = Shoko::Shared::DisplayMetadataFingerprint

          include Shoko::Application::Ports::Outbound::DisplayMetadataCache

          VERSION = 1
          CACHE_SUBDIR = File.join('book_metadata', 'v1')

          def initialize(cache_root:, atomic_file_writer: Shoko::Adapters::Storage::AtomicFileWriter)
            @cache_root = cache_root
            @atomic_file_writer = atomic_file_writer
          end

          def fetch(path:, size:, modified:)
            payload = read_payload(cache_path(path))
            return nil unless valid_payload?(payload, path: path, size: size, modified: modified)

            cache_entry(payload)
          end

          def write_success(path:, size:, modified:, metadata:)
            write_payload(
              path,
              base_payload(path: path, size: size, modified: modified)
                .merge('status' => 'ok', 'metadata' => normalize_metadata(metadata))
            )
          end

          def write_error(path:, size:, modified:, error_class:, error_message:)
            write_payload(
              path,
              base_payload(path: path, size: size, modified: modified)
                .merge(
                  'status' => 'error',
                  'error_class' => error_class.to_s,
                  'error_message' => error_message.to_s
                )
            )
          end

          private

          def cache_entry(payload)
            status = payload['status'].to_s
            return success_entry(payload) if status == 'ok'
            return error_entry(payload) if status == 'error'

            nil
          end

          def success_entry(payload)
            {
              status: :ok,
              metadata: Shoko::Shared::HashNormalizer.deep_symbolize(payload['metadata'] || {}),
            }
          end

          def error_entry(payload)
            {
              status: :error,
              error_class: payload['error_class'].to_s,
              error_message: payload['error_message'].to_s,
            }
          end

          def read_payload(path)
            return nil unless File.exist?(path)

            parsed = JSON.parse(File.read(path))
            return parsed if parsed.is_a?(Hash)

            delete_cache_file(path)
            nil
          rescue JSON::ParserError, ArgumentError, TypeError, SystemCallError
            delete_cache_file(path)
            nil
          end

          def write_payload(path, payload)
            @atomic_file_writer.write(cache_path(path), JSON.generate(payload))
          end

          def valid_payload?(payload, path:, size:, modified:)
            return false unless payload.is_a?(Hash)
            return false unless payload['version'].to_i == VERSION

            fingerprint = DisplayMetadataFingerprint
            return false unless payload['path'].to_s == path.to_s
            return false unless fingerprint.size(payload['size']) == fingerprint.size(size)
            return false unless fingerprint.modified(payload['modified']) == fingerprint.modified(modified)

            %w[ok error].include?(payload['status'].to_s)
          end

          def base_payload(path:, size:, modified:)
            {
              'version' => VERSION,
              'path' => path.to_s,
              'size' => DisplayMetadataFingerprint.size(size),
              'modified' => DisplayMetadataFingerprint.modified(modified),
            }
          end

          def normalize_metadata(metadata)
            return {} unless metadata.is_a?(Hash)

            metadata.each_with_object({}) do |(key, value), acc|
              acc[key.to_s] = normalize_metadata_value(value)
            end
          end

          def normalize_metadata_value(value)
            case value
            when Array
              value.map { |item| normalize_metadata_scalar(item) }
            when Hash
              normalize_metadata(value)
            else
              normalize_metadata_scalar(value)
            end
          end

          def normalize_metadata_scalar(value)
            return nil if value.nil?
            return value if value == true || value == false || value.is_a?(Numeric)

            value.to_s
          end

          def cache_path(path)
            File.join(cache_dir, "#{Digest::SHA256.hexdigest(path.to_s)}.json")
          end

          def cache_dir
            File.join(@cache_root.to_s, CACHE_SUBDIR)
          end

          # Best-effort cleanup of a stale or corrupt cache file. Called
          # from `read_payload` when a payload fails validation or JSON
          # parsing; the cleanup itself must not crash the read path,
          # which is why a `SystemCallError` here (typically permission
          # denied on the cache directory) translates to nil. The next
          # read's validity check will reject the stale entry anyway.
          # Exempt from `no_rescue_literal_default` for this reason —
          # see `EXEMPT_OFFENDERS` in the spec.
          def delete_cache_file(path)
            FileUtils.rm_f(path)
          rescue SystemCallError
            nil
          end
        end
      end
    end
  end
end
