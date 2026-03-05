# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          module AnnotationMarkup
            # Finds balanced style marker pairs in annotation text.
            class PairFinder
              def initialize(text, markers:, literal_styles:)
                @text = text.to_s
                @markers = markers
                @literal_styles = literal_styles
                @open_at = {}
                @close_at = {}
                @stack = []
              end

              def find_pairs
                idx = 0
                while idx < @text.length
                  idx = advance_index(idx)
                  break if idx >= @text.length

                  handle_marker(idx)
                  idx += 1
                end
                [@open_at, @close_at]
              end

              private

              def advance_index(idx)
                escaped?(idx) ? idx + 2 : idx
              end

              def escaped?(idx)
                @text[idx] == '\\' && (idx + 1) < @text.length
              end

              def handle_marker(idx)
                style = @markers[@text[idx]]
                return unless style

                can_open, can_close = delimiter_flags(idx)
                if literal_mode?
                  close_current_marker(idx, can_close)
                elsif closing_current_marker?(idx, can_close)
                  close_last_marker(idx)
                elsif can_open
                  open_marker(idx, style)
                end
              end

              def literal_mode?
                @stack.any? { |entry| @literal_styles.include?(entry[:style]) }
              end

              def close_current_marker(idx, can_close)
                return unless closing_current_marker?(idx, can_close)

                close_last_marker(idx)
              end

              def closing_current_marker?(idx, can_close)
                can_close && @stack.last && @stack.last[:marker] == @text[idx]
              end

              def close_last_marker(idx)
                open = @stack.pop
                @open_at[open[:index]] = open[:style]
                @close_at[idx] = open[:style]
              end

              def open_marker(idx, style)
                @stack << { marker: @text[idx], style: style, index: idx }
              end

              def delimiter_flags(idx)
                prev, nxt = neighbor_chars(idx)
                prev_data = char_context(prev)
                next_data = char_context(nxt)
                can_open = !next_data[:whitespace] && (prev_data[:whitespace] || prev_data[:punct] || prev.nil?)
                can_close = !prev_data[:whitespace] && (next_data[:whitespace] || next_data[:punct] || nxt.nil?)
                [can_open, can_close]
              end

              def neighbor_chars(idx)
                prev = idx.positive? ? @text[idx - 1] : nil
                nxt = (idx + 1) < @text.length ? @text[idx + 1] : nil
                [prev, nxt]
              end

              def char_context(char)
                whitespace = whitespace?(char)
                word = word_char?(char)
                {
                  whitespace: whitespace,
                  punct: char && !whitespace && !word,
                }
              end

              def whitespace?(char)
                char.nil? || char.match?(/\s/)
              end

              def word_char?(char)
                return false if char.nil?

                char.match?(/\p{Alnum}/)
              rescue Shoko::Error
                char.match?(/[A-Za-z0-9]/)
              end
            end
          end
        end
      end
    end
  end
end
