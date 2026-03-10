# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../../../core/models/session/config_snapshot'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Archives pre-hex persisted roots when the stored config schema is outdated.
        class SessionSchemaResetGuard
          def initialize(config_storage:, cache_paths:, logger: nil, schema_version: nil)
            @config_storage = config_storage
            @cache_paths = cache_paths
            @logger = logger
            @schema_version = schema_version || Shoko::Core::Models::Session::ConfigSnapshot::SCHEMA_VERSION
          end

          def ensure_current_schema!
            payload = persisted_config_payload
            return :pass unless payload.is_a?(Hash)

            persisted = payload[:schema_version]
            return :pass if persisted.to_i == @schema_version

            timestamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
            config_archive = archive_root(@config_storage.config_dir, timestamp)
            cache_archive = archive_root(@cache_paths.cache_root, timestamp)
            @logger&.info(
              'session.schema_reset',
              from_schema_version: persisted,
              to_schema_version: @schema_version,
              config_archive: config_archive,
              cache_archive: cache_archive
            )
            {
              config_archive: config_archive,
              cache_archive: cache_archive,
            }
          end

          private

          def persisted_config_payload
            config_file = @config_storage.config_file
            return nil unless @config_storage.file_exist?(config_file)

            content = @config_storage.read_file(config_file)
            return nil if content.nil? || content.empty?

            JSON.parse(content, symbolize_names: true)
          rescue JSON::ParserError
            invalid_persisted_config_payload
          end

          def archive_root(root, timestamp)
            return nil unless root && File.exist?(root)

            archive_path = unique_archive_path(File.dirname(root), timestamp)
            FileUtils.mv(root, archive_path)
            archive_path
          end

          def unique_archive_path(parent_dir, timestamp)
            base = File.join(parent_dir, "shoko-pre-hex-v#{@schema_version}-#{timestamp}")
            return base unless File.exist?(base)

            suffix = 1
            loop do
              candidate = "#{base}-#{suffix}"
              return candidate unless File.exist?(candidate)

              suffix += 1
            end
          end

          def invalid_persisted_config_payload
            { schema_version: nil }
          end
        end
      end
    end
  end
end
