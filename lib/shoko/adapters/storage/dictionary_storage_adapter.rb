# frozen_string_literal: true

require 'fileutils'
require_relative '../../core/ports/outbound/dictionary_storage'
require_relative 'config_paths'

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
        rescue StandardError
          default_databases_path
        end

        def ensure_databases_path(configured_path)
          path = resolve_databases_path(configured_path)
          FileUtils.mkdir_p(path)
          path
        rescue StandardError
          fallback = default_databases_path
          FileUtils.mkdir_p(fallback)
          fallback
        end

        def databases_present?(configured_path)
          path = resolve_databases_path(configured_path)
          return false unless path && Dir.exist?(path)

          Dir.glob(File.join(path, '*.sqlite3')).any?
        rescue StandardError
          false
        end

        def remove_databases_path(configured_path)
          path = resolve_databases_path(configured_path)
          return unless path && File.directory?(path)

          real = safe_realpath(path)
          return unless real

          FileUtils.rm_rf(real)
        rescue StandardError
          nil
        end

        def display_path(path)
          expanded = File.expand_path(path.to_s)
          home = Dir.home
          return expanded unless home && expanded.start_with?(home)

          expanded.sub(/\A#{Regexp.escape(home)}/, '~')
        rescue StandardError
          path.to_s
        end

        private

        def safe_realpath(path)
          real = File.realpath(path)
          return nil if real == '/' || real == Dir.home

          real
        rescue StandardError
          return nil unless File.exist?(path)

          real = File.expand_path(path)
          return nil if real == '/' || real == Dir.home

          real
        end
      end
    end
  end
end
