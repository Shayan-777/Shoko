# frozen_string_literal: true

require 'json'
require_relative 'file_store_utils'
require_relative '../../config_paths'

module Shoko
  module Adapters
    module Storage
      module Repositories
        module Storage
          # Base class for file-backed JSON stores (annotations, bookmarks,
          # progress).
          #
          # On disk each store is a versioned envelope:
          #
          #   { "schema_version" => <Integer>, "entries" => { ...store data... } }
          #
          # Files written before versioning existed are bare hashes (the entries
          # map at the top level). They load as LEGACY_VERSION and are rewritten
          # into the envelope on the next save, so existing user data upgrades in
          # place without a separate migration step.
          #
          # Subclasses whose on-disk record shape changed across versions set a
          # higher SCHEMA_VERSION and override #migrate_entries to upgrade older
          # payloads at load time. Because the upgrade runs inside #load_all, it
          # flows through both reads and the read-modify-write of add/update/
          # delete, so the next save persists the current shape.
          class BaseFileStore
            # Version assumed for a pre-envelope bare-hash file.
            LEGACY_VERSION = 1
            # Current on-disk schema version; subclasses bump this when their
            # record shape changes.
            SCHEMA_VERSION = 1

            def initialize(file_writer:, logger: nil)
              @file_writer = file_writer
              @logger = logger
            end

            protected

            attr_reader :file_writer, :logger

            def load_all
              unwrap(FileStoreUtils.load_json_or_empty(file_path, logger: @logger))
            end

            def save_all(entries)
              payload = JSON.pretty_generate('schema_version' => schema_version, 'entries' => entries)
              file_writer.write(file_path, payload)
            end

            def file_path
              Adapters::Storage::ConfigPaths.config_path(self.class::FILE_NAME)
            end

            def schema_version
              self.class::SCHEMA_VERSION
            end

            # Upgrade an entries map loaded from +from_version+ to the current
            # shape. Default: no shape change across versions. Stores that changed
            # their record shape override this.
            def migrate_entries(entries, _from_version)
              entries
            end

            private

            def unwrap(raw)
              return {} unless raw.is_a?(Hash)

              if versioned_envelope?(raw)
                migrate_entries(raw['entries'], raw['schema_version'].to_i)
              else
                migrate_entries(raw, LEGACY_VERSION)
              end
            end

            def versioned_envelope?(raw)
              raw.key?('schema_version') && raw['entries'].is_a?(Hash)
            end
          end
        end
      end
    end
  end
end
