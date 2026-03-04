# frozen_string_literal: true

require 'fileutils'
require_relative '../../core/ports/outbound/dictionary_storage'
require_relative 'config_paths'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Storage
      # Adapter implementing dictionary database path/storage policy.
      class DictionaryStorageAdapter
        include Core::Ports::Outbound::DictionaryStorage

        def default_databases_path
          ConfigPaths.config_path('dictionary')
        end

        def resolve_databases_path(configured_path)
          path = configured_path.to_s.strip
          return default_databases_path if path.empty?

          File.expand_path(path)
        rescue StandardError => e
          raise_storage_error('resolve_databases_path', configured_path, e)
        end

        def ensure_databases_path(configured_path)
          path = resolve_databases_path(configured_path)
          FileUtils.mkdir_p(path)
          path
        rescue StandardError => e
          raise_storage_error('ensure_databases_path', configured_path, e)
        end

        def databases_present?(configured_path)
          path = resolve_databases_path(configured_path)
          return false unless path && Dir.exist?(path)

          Dir.glob(File.join(path, '*.sqlite3')).any?
        rescue StandardError => e
          raise_storage_error('databases_present?', configured_path, e)
        end

        def remove_databases_path(configured_path)
          path = resolve_databases_path(configured_path)
          return unless path && File.directory?(path)

          real = safe_realpath!(path)
          FileUtils.rm_rf(real)
        rescue StandardError => e
          raise_storage_error('remove_databases_path', configured_path, e)
        end

        def display_path(path)
          expanded = File.expand_path(path.to_s)
          home = Dir.home
          return expanded unless home && expanded.start_with?(home)

          expanded.sub(/\A#{Regexp.escape(home)}/, '~')
        rescue StandardError => e
          raise_storage_error('display_path', path, e)
        end

        private

        def safe_realpath!(path)
          real = File.realpath(path)
          raise Shoko::StorageError.new('resolve_realpath', path, 'unsafe target path') if real == '/' || real == Dir.home

          real
        rescue StandardError => e
          raise_storage_error('resolve_realpath', path, e)
        end

        def raise_storage_error(operation, path, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::StorageError.new(operation, path.to_s, error.message)
        end
      end
    end
  end
end
