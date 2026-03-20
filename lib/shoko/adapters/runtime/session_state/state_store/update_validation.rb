# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Validation helpers for state updates applied through StateStore.
        module StateStoreUpdateValidation
          private

          def validate_state_update(path, value)
            path_array = Array(path)

            case path_array
            when %i[reader current_chapter]
              validate_reader_update(value)
            when %i[config view_mode], %i[config download_source], %i[config theme], %i[config kitty_images]
              validate_config_update(path_array.last, value)
            when %i[ui terminal_width], %i[ui terminal_height]
              validate_terminal_dimension(value)
            end
          end

          def validate_reader_update(value)
            raise ArgumentError, 'current_chapter must be non-negative' if value.negative?
          end

          def validate_config_update(key, value)
            case key
            when :view_mode
              validate_view_mode(value)
            when :download_source
              validate_download_source(value)
            when :theme
              validate_theme(value)
            when :kitty_images
              validate_kitty_images(value)
            end
          end

          def validate_view_mode(value)
            raise ArgumentError, 'invalid view_mode' unless %i[single split].include?(value)
          end

          def validate_download_source(value)
            raise ArgumentError, 'invalid download_source' unless Shoko::Shared::DownloadSourcePolicy.valid?(value)
          end

          def validate_theme(value)
            raise ArgumentError, "invalid theme: #{value.inspect}" unless Shoko::Shared::ThemePolicy.valid?(value)
          end

          def validate_kitty_images(value)
            raise ArgumentError, 'kitty_images must be boolean' unless [true, false].include?(value)
          end

          def validate_terminal_dimension(value)
            raise ArgumentError, 'terminal dimensions must be positive' if value <= 0
          end
        end
      end
    end
  end
end
