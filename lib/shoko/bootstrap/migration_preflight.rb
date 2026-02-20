# frozen_string_literal: true

require_relative '../adapters/storage/config_paths'
require_relative '../adapters/storage/cache_paths'

module Shoko
  module Bootstrap
        # Startup gate that blocks runtime when v2 migration is required.
        module MigrationPreflight
          MIGRATION_MARKER = '.migrated_v2'
          LEGACY_CONFIG_FILES = %w[
            config.json
            annotations.json
            bookmarks.json
            progress.json
            recent.json
            epub_cache.json
          ].freeze

          class MigrationRequiredError < StandardError; end

          module_function

          def ensure_migrated!
            return unless migration_required?

            raise MigrationRequiredError, migration_required_message
          end

          def migration_required?
            return false if marker_present?

            legacy_data_present?
          end

          def marker_path
            File.join(config_root, MIGRATION_MARKER)
          end

          def config_root
            Shoko::Adapters::Storage::ConfigPaths.config_root
          end

          def cache_root
            Shoko::Adapters::Storage::CachePaths.cache_root
          end

          def legacy_paths
            files = LEGACY_CONFIG_FILES.map { |name| File.join(config_root, name) }
            files << cache_root
            files.select { |path| File.exist?(path) }
          end

          def marker_present?
            File.file?(marker_path)
          rescue StandardError
            false
          end

          def legacy_data_present?
            return false unless Dir.exist?(config_root) || Dir.exist?(cache_root)

            legacy_paths.any?
          rescue StandardError
            false
          end

          def migration_required_message
            lines = [
              'Shoko data migration required before startup.',
              "Run: bin/migrate-v2",
              "Marker expected at: #{marker_path}"
            ]
            present = legacy_paths
            unless present.empty?
              lines << 'Detected legacy paths:'
              present.each { |path| lines << "  - #{path}" }
            end
            lines.join("\n")
          end
        end
      end
end
