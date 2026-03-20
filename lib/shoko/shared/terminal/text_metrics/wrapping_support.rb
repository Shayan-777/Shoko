# frozen_string_literal: true

module Shoko
  module Shared
    module Terminal
      module TextMetrics
        # Truncation, padding, and cell/plain-text wrapping helpers.
        module WrappingSupport
          PlainWrapState = Struct.new(:lines, :current_line, :current_width)
          CellWrapState = Struct.new(:lines, :line, :line_width, :column, :start_column)

          def wrap_plain_text(line, width)
            source = line.to_s
            width_i = width.to_i
            cached_wrap_plain_text(source, width_i) { compute_wrapped_plain_text(source, width_i) }
          end

          def wrap_cells(text, width, start_column: 0)
            max_width = width.to_i
            return [''] if max_width <= 0

            state = CellWrapState.new([], +'', 0, start_column.to_i, start_column.to_i)

            text.to_s.each_grapheme_cluster do |cluster|
              process_wrap_cell_cluster(state, cluster, max_width)
            end

            finalize_cell_wrap(state)
          end

          private

          def compute_wrapped_plain_text(source, width_i)
            normalized = expand_tabs(source)
            return [''] if normalized.empty?
            return [normalized] if width_i <= 0

            state = PlainWrapState.new([], +'', 0)
            normalized.split(/\s+/).each { |word| append_plain_wrap_word(state, word, width_i) }
            finalize_plain_wrap(state)
          end

          def append_plain_wrap_word(state, word, width_i)
            return if word.nil? || word.empty?

            word_width = visible_length(word)
            return append_oversized_plain_word(state, word, width_i) if word_width > width_i
            return start_plain_wrap_word(state, word, word_width) if state.current_width.zero?
            if plain_wrap_word_fits?(state, word_width, width_i)
              return append_fitting_plain_word(state, word, word_width)
            end

            push_plain_wrap_line(state)
            start_plain_wrap_word(state, word, word_width)
          end

          def append_oversized_plain_word(state, word, width_i)
            push_plain_wrap_line(state)
            chunks = wrap_cells(word, width_i)
            return if chunks.empty?

            state.lines.concat(chunks[0...-1])
            tail = chunks.last.to_s
            if tail.empty?
              reset_plain_wrap_line(state)
            else
              start_plain_wrap_word(state, tail, visible_length(tail))
            end
          end

          def start_plain_wrap_word(state, word, width)
            state.current_line.replace(word)
            state.current_width = width
          end

          def plain_wrap_word_fits?(state, word_width, width_i)
            state.current_width + 1 + word_width <= width_i
          end

          def append_fitting_plain_word(state, word, word_width)
            state.current_line << ' ' unless state.current_line.empty?
            state.current_line << word
            state.current_width += 1 + word_width
          end

          def push_plain_wrap_line(state)
            state.lines << state.current_line.dup unless state.current_line.empty?
            reset_plain_wrap_line(state)
          end

          def reset_plain_wrap_line(state)
            state.current_line.clear
            state.current_width = 0
          end

          def finalize_plain_wrap(state)
            state.lines << state.current_line.dup unless state.current_line.empty?
            state.lines.empty? ? [''] : state.lines
          end

          def process_wrap_cell_cluster(state, cluster, max_width)
            return wrap_cell_newline(state) if cluster == "\n"

            cluster = ' ' if cluster == "\r"
            return wrap_cell_tab(state, max_width) if cluster == "\t"

            append_wrap_cell_cluster(state, cluster, max_width)
          end

          def wrap_cell_newline(state)
            state.lines << state.line.dup
            reset_cell_wrap_line(state)
          end

          def wrap_cell_tab(state, max_width)
            spaces = TAB_SIZE - (state.column % TAB_SIZE)
            spaces.times do
              wrap_cell_space(state, max_width)
            end
          end

          def wrap_cell_space(state, max_width)
            wrap_cell_line_if_needed(state, 1, max_width)
            state.line << ' '
            state.line_width += 1
            state.column += 1
          end

          def append_wrap_cell_cluster(state, cluster, max_width)
            cluster_width = display_width_for(cluster)
            return if cluster_width <= 0 || cluster_width > max_width

            wrap_cell_line_if_needed(state, cluster_width, max_width)
            return if cluster_width > (max_width - state.line_width)

            state.line << cluster
            state.line_width += cluster_width
            state.column += cluster_width
          end

          def wrap_cell_line_if_needed(state, cluster_width, max_width)
            return unless state.line_width.positive? && (state.line_width + cluster_width > max_width)

            state.lines << state.line.dup
            reset_cell_wrap_line(state)
          end

          def reset_cell_wrap_line(state)
            state.line.clear
            state.line_width = 0
            state.column = state.start_column
          end

          def finalize_cell_wrap(state)
            state.lines << state.line.dup
            state.lines.empty? ? [''] : state.lines
          end
        end
      end
    end
  end
end
