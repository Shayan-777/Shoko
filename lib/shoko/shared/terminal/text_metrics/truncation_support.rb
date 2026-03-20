# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Truncation and padding helpers layered on top of visible-length primitives.
        module TruncationSupport
          TruncationState = Struct.new(:current_width, :column)

          def truncate_to(text, width, start_column: 0)
            max_width = width.to_i
            return '' if max_width <= 0

            str = text.to_s
            return '' if str.empty?
            return truncated_ascii_fast_path(str, max_width) if truncated_ascii_fast_path?(str, max_width)
            return str if truncation_passthrough?(str, max_width)

            truncate_tokens(str, max_width, start_column.to_i)
          end

          def pad_right(text, width, start_column: 0, pad: ' ')
            pad_text(:right, text, width, start_column: start_column, pad: pad)
          end

          def pad_left(text, width, start_column: 0, pad: ' ')
            pad_text(:left, text, width, start_column: start_column, pad: pad)
          end

          def pad_center(text, width, start_column: 0, pad: ' ')
            pad_text(:center, text, width, start_column: start_column, pad: pad)
          end

          private

          def truncated_ascii_fast_path?(str, max_width)
            ascii_fast_path_enabled? &&
              fast_ascii_truncate_candidate?(str) &&
              max_width < str.bytesize
          end

          def truncated_ascii_fast_path(str, max_width)
            str.byteslice(0, max_width).to_s
          end

          def truncation_passthrough?(str, max_width)
            return false if str.include?("\t") || str.include?("\n") || str.include?("\r")

            max_width >= visible_length(str)
          end

          def truncate_tokens(str, max_width, start_column)
            buffer = +''
            state = TruncationState.new(0, start_column)

            str.scan(TOKEN_REGEX).each do |token|
              append_truncated_token(buffer, token, max_width, state)
              break if state.current_width >= max_width
            end

            buffer
          end

          def append_truncated_token(buffer, token, max_width, state)
            return if state.current_width >= max_width
            return append_ansi_token(buffer, token) if token.start_with?("\e[")
            return if token == "\e"

            remaining = max_width - state.current_width
            case token
            when "\t"
              append_tab_token(buffer, remaining, state)
            when "\n", "\r"
              append_newline_token(buffer, remaining, state)
            else
              append_visible_token(buffer, token, remaining, state)
            end
          end

          def append_ansi_token(buffer, token)
            buffer << token
          end

          def append_tab_token(buffer, remaining, state)
            spaces = TAB_SIZE - (state.column % TAB_SIZE)
            take = [spaces, remaining].min
            buffer << (' ' * take)
            advance_truncation_state(state, take)
          end

          def append_newline_token(buffer, remaining, state)
            return if remaining < 1

            buffer << ' '
            advance_truncation_state(state, 1)
          end

          def append_visible_token(buffer, token, remaining, state)
            token_width = display_width_for(token)
            return if token_width > remaining

            buffer << token
            advance_truncation_state(state, token_width)
          end

          def advance_truncation_state(state, width)
            state.current_width += width
            state.column += width
          end

          def pad_text(mode, text, width, start_column:, pad:)
            max_width = width.to_i
            return '' if max_width <= 0

            clipped = truncate_to(text.to_s, max_width, start_column: start_column)
            pad_length = max_width - visible_length(clipped)
            return clipped unless pad_length.positive?

            apply_padding(mode, clipped, pad.to_s, pad_length)
          end

          def apply_padding(mode, clipped, pad, pad_length)
            case mode
            when :left
              (pad * pad_length) + clipped
            when :center
              left = pad_length / 2
              right = pad_length - left
              (pad * left) + clipped + (pad * right)
            else
              clipped + (pad * pad_length)
            end
          end
        end
      end
    end
  end
end
