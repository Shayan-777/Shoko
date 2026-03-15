# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Shared helpers for resolving configuration values from the state store.
          # Accepts either a config_reader port or a rendering context with config_reader.
          module ConfigHelpers
            module_function

            def config_reader_from(config)
              return nil unless config
              return config if config.respond_to?(:line_spacing)

              if config.is_a?(Struct)
                return config_reader_from(config[:config_reader]) if config.members.include?(:config_reader)
                return config if config.members.include?(:line_spacing)
              end
              if config.is_a?(Data)
                values = config.to_h
                return config_reader_from(values[:config_reader]) if values.key?(:config_reader)
              end
              if config.is_a?(Hash)
                reader = config.each_with_object({}) do |(key, value), normalized|
                  normalized[key.is_a?(String) ? key.to_sym : key] = value
                end[:config_reader]
                return config_reader_from(reader) if reader
              end

              raise ArgumentError, 'config must expose config-like accessors'
            end

            def line_spacing(config)
              reader = config_reader_from(config)
              return Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING unless reader

              reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
            end

            def highlight_quotes?(config_reader)
              return true unless config_reader

              value = config_reader.highlight_quotes
              value.nil? || value
            end

            def highlight_keywords?(config_reader)
              return false unless config_reader

              !!config_reader.highlight_keywords
            end
          end
        end
      end
    end
  end
end
