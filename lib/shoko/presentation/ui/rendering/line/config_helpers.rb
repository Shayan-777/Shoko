# frozen_string_literal: true

module Shoko
  module Presentation::Ui::Components
    module Reading
      # Shared helpers for resolving configuration values from the state store.
      # Accepts either a config_reader port or a rendering context with config_reader.
      module ConfigHelpers
        module_function

        # Extract config_reader from various input types
        def config_reader_from(config)
          # If it's already a config reader (responds to line_spacing)
          return config if config.respond_to?(:line_spacing)

          # If it's a rendering context with config_reader
          return config.config_reader if config.respond_to?(:config_reader) && config.config_reader

          nil
        end

        def line_spacing(config)
          reader = config_reader_from(config)
          return Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING unless reader

          reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        rescue StandardError
          Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        end

        def highlight_quotes?(config_reader)
          return true unless config_reader.respond_to?(:highlight_quotes)

          value = config_reader.highlight_quotes
          value.nil? || value
        rescue StandardError
          true
        end

        def highlight_keywords?(config_reader)
          return false unless config_reader.respond_to?(:highlight_keywords)

          !!config_reader.highlight_keywords
        rescue StandardError
          false
        end
      end
    end
  end
end
