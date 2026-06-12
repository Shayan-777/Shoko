# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'shoko/application/ports/outbound/state/config_snapshot'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Resets persisted state whose schema is outdated or unreadable.
        #
        # Scope is deliberately narrow: only `config.json` (renamed to an
        # adjacent, discoverable archive file) and the cache root (rebuildable
        # from the source books) are touched. User data living next to the
        # config — annotations, bookmarks, progress, recent files, RSS feeds,
        # downloaded books — is never archived or deleted by a schema reset.
        class SessionSchemaResetGuard
          def initialize(config_storage:, cache_paths:, logger: nil, schema_version: nil)
            @config_storage = config_storage
            @cache_paths = cache_paths
            @logger = logger
            @schema_version = schema_version ||
                              Shoko::Application::Ports::Outbound::State::ConfigSnapshot::SCHEMA_VERSION
          end

          def ensure_current_schema!
            payload = persisted_config_payload
            return :pass unless payload.is_a?(Hash)

            persisted = payload[:schema_version]
            return :pass if persisted.to_i == @schema_version

            timestamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
            archives = schema_reset_archives(persisted, timestamp)
            log_schema_reset(persisted, archives)
            archives
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

          # Renames config.json to config-pre-v<N>-<ts>.json in the same
          # directory, so the previous settings stay next to the new file
          # instead of disappearing into a moved directory tree.
          def archive_config_file(timestamp)
            config_file = @config_storage.config_file
            return nil unless config_file && File.exist?(config_file)

            archive_path = unique_archive_path(
              File.join(File.dirname(config_file), "config-pre-v#{@schema_version}-#{timestamp}"),
              extension: '.json'
            )
            File.rename(config_file, archive_path)
            archive_path
          end

          def archive_cache_root(timestamp)
            root = @cache_paths.cache_root
            return nil unless root && File.exist?(root)

            archive_path = unique_archive_path(
              File.join(File.dirname(root), "shoko-pre-hex-v#{@schema_version}-#{timestamp}")
            )
            FileUtils.mv(root, archive_path)
            archive_path
          end

          def unique_archive_path(base, extension: '')
            candidate = "#{base}#{extension}"
            return candidate unless File.exist?(candidate)

            suffix = 1
            loop do
              candidate = "#{base}-#{suffix}#{extension}"
              return candidate unless File.exist?(candidate)

              suffix += 1
            end
          end

          def invalid_persisted_config_payload
            { schema_version: nil }
          end

          def schema_reset_archives(persisted, timestamp)
            {
              from_schema_version: persisted,
              config_archive: archive_config_file(timestamp),
              cache_archive: archive_cache_root(timestamp),
            }
          end

          def log_schema_reset(persisted, archives)
            @logger&.info(
              'session.schema_reset',
              from_schema_version: persisted,
              to_schema_version: @schema_version,
              config_archive: archives[:config_archive],
              cache_archive: archives[:cache_archive]
            )
          end
        end
      end
    end
  end
end
