# frozen_string_literal: true

require 'shoko/core/policies/download_source_policy'
require 'shoko/core/policies/theme_policy'

module Shoko
  module Application
    module State
      class StateStore
        # Encapsulates configuration load/save concerns for the runtime
        # state. The store holds the config in memory; this collaborator
        # bridges it to the config-storage outbound port.
        class ConfigPersistence
          def initialize(config_storage:, symbol_keys:, line_spacing_aliases:, log_warn:, log_error:)
            @config_storage = config_storage
            @symbol_keys = symbol_keys
            @line_spacing_aliases = line_spacing_aliases
            @log_warn = log_warn
            @log_error = log_error
          end

          # Config persistence is an isolation boundary: the config file is
          # external input (possibly corrupt or unwritable) and a failure here
          # must degrade to in-memory defaults, never crash startup or a save.
          def save(config:, config_file:, config_dir:)
            ensure_config_dir(config_dir)
            payload = JSON.pretty_generate(config)
            @config_storage.atomic_write(config_file, payload)
          # resilient-boundary
          rescue StandardError => e
            record_config_write_error(e, config_file)
          end

          def load(config:, config_file:)
            return {} unless @config_storage.file_exist?(config_file)

            data = parse_config_file(config_file)
            return {} unless data.is_a?(Hash)

            extract_updates(data, config)
          # resilient-boundary
          rescue StandardError => e
            record_config_load_error(e, config_file)
            {}
          end

          private

          def ensure_config_dir(config_dir)
            @config_storage.ensure_config_dir
          # resilient-boundary
          rescue StandardError => e
            record_config_dir_error(e, config_dir)
          end

          def parse_config_file(path)
            content = @config_storage.read_file(path)
            return nil unless content

            JSON.parse(content, symbolize_names: true)
          # resilient-boundary
          rescue StandardError => e
            record_config_parse_error(e, path)
            nil
          end

          def record_config_write_error(error, config_file)
            @log_error.call('config.write failed', error: "#{error.class}: #{error.message}", path: config_file)
          end

          def record_config_load_error(error, config_file)
            @log_warn.call('config.load failed; using defaults',
                           error: "#{error.class}: #{error.message}", path: config_file)
          end

          def record_config_dir_error(error, config_dir)
            @log_warn.call('config.ensure_dir failed', error: "#{error.class}: #{error.message}", path: config_dir)
          end

          def record_config_parse_error(error, path)
            @log_warn.call('config.parse failed; using defaults',
                           error: "#{error.class}: #{error.message}", path: path)
          end

          def extract_updates(data, existing_config)
            config_updates = {}
            data.each do |key, value|
              next unless existing_config.key?(key)

              value = normalize_config_value(key, value)
              next unless valid_config_value?(key, value)

              config_updates[[:config, key]] = value
            end
            config_updates
          end

          def normalize_config_value(key, value)
            normalized = normalize_symbol_value(key, value)
            normalized = @line_spacing_aliases.fetch(normalized, normalized) if key == :line_spacing
            if key == :theme
              normalized = Shoko::Core::Policies::ThemePolicy.normalize(normalized) || Shoko::Core::Policies::ThemePolicy.default_id
            end
            normalized
          end

          def normalize_symbol_value(key, value)
            return value unless @symbol_keys.include?(key)
            return value if value.nil? || value.is_a?(Symbol)

            value.to_s.to_sym
          end

          def valid_config_value?(key, value)
            case key
            when :view_mode
              %i[single split].include?(value)
            when :download_source
              Shoko::Core::Policies::DownloadSourcePolicy.valid?(value)
            when :kitty_images
              value.is_a?(TrueClass) || value.is_a?(FalseClass)
            else
              true
            end
          end
        end
      end
    end
  end
end
