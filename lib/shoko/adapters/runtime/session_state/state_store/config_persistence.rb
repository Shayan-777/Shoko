# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        class StateStore
          # Encapsulates configuration load/save concerns for the runtime state.
          class ConfigPersistence
            def initialize(config_storage:, symbol_keys:, line_spacing_aliases:, log_warn:, log_error:)
              @config_storage = config_storage
              @symbol_keys = symbol_keys
              @line_spacing_aliases = line_spacing_aliases
              @log_warn = log_warn
              @log_error = log_error
            end

            def save(config:, config_file:, config_dir:)
              ensure_config_dir(config_dir)
              payload = JSON.pretty_generate(config)
              @config_storage.atomic_write(config_file, payload)
            # resilient-boundary
            rescue StandardError => e
              @log_error.call('config.write failed', error: e.message, path: config_file)
            end

            def load(config:, config_file:)
              return {} unless @config_storage.file_exist?(config_file)

              data = parse_config_file(config_file)
              return {} unless data.is_a?(Hash)

              extract_updates(data, config)
            # resilient-boundary
            rescue StandardError => e
              @log_warn.call('config.load failed; using defaults', error: e.message, path: config_file)
              {}
            end

            private

            def ensure_config_dir(config_dir)
              @config_storage.ensure_config_dir
            # resilient-boundary
            rescue StandardError => e
              @log_warn.call('config.ensure_dir failed', error: e.message, path: config_dir)
            end

            def parse_config_file(path)
              content = @config_storage.read_file(path)
              return nil unless content

              JSON.parse(content, symbolize_names: true)
            # resilient-boundary
            rescue StandardError => e
              @log_warn.call('config.parse failed; using defaults', error: e.message, path: path)
              nil
            end

            def extract_updates(data, current_config)
              config_updates = {}
              data.each do |key, value|
                next unless current_config.key?(key)

                value = value.to_sym if @symbol_keys.include?(key) && value.respond_to?(:to_sym)
                value = @line_spacing_aliases.fetch(value, value) if key == :line_spacing
                next unless valid_config_value?(key, value)

                config_updates[[:config, key]] = value
              end
              config_updates
            end

            def valid_config_value?(key, value)
              case key
              when :view_mode
                %i[single split].include?(value)
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
end
