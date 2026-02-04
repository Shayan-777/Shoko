# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Terminal
        # Utility helpers for measuring and truncating strings (with ANSI support)
        # while respecting grapheme clusters and terminal cell widths.
        module TextMetrics
          require_relative '../../../shared/unicode_display_width'
          DISPLAY_WIDTH = ->(str) { Shoko::Shared::UnicodeDisplayWidth.width(str) }
          TAB_SIZE = 4
          CSI_REGEX = %r{\e\[[0-?]*[ -/]*[@-~]}
          ANSI_REGEX = CSI_REGEX
          TOKEN_REGEX = /#{CSI_REGEX}|\X/m

          module_function

          def visible_length(text)
            # Fast path: directly compute display width without building cell data
            expanded = expand_tabs(strip_ansi(text.to_s))
            width = 0
            expanded.each_grapheme_cluster do |cluster|
              width += display_width_for(cluster)
            end
            width
          end

          def cell_data_for(text)
            expanded = expand_tabs(text.to_s)
            cells = []
            char_index = 0
            screen_x = 0

            expanded.each_grapheme_cluster do |cluster|
              grapheme_length = cluster.length
              display_width = display_width_for(cluster)

              cells << {
                cluster: cluster,
                char_start: char_index,
                char_end: char_index + grapheme_length,
                display_width: display_width,
                screen_x: screen_x,
              }

              char_index += grapheme_length
              screen_x += display_width
            end

            cells
          end

          def strip_ansi(text)
            text.to_s.gsub(ANSI_REGEX, '')
          end

          def display_width_for(cluster)
            return TAB_SIZE if cluster == "\t"
            return 0 if cluster == "\u00AD"

            width = DISPLAY_WIDTH.call(cluster)
            width = 1 if width <= 0 && !cluster.empty?
            width
          rescue StandardError
            cluster.length
          end

          def expand_tabs(text, tab_size: TAB_SIZE)
            column = 0
            buffer = +''
            text.to_s.each_grapheme_cluster do |cluster|
              if cluster == "\t"
                spaces = tab_size - (column % tab_size)
                buffer << (' ' * spaces)
                column += spaces
              else
                buffer << cluster
                column += display_width_for(cluster)
              end
            end
            buffer
          end

          def wrap_plain_text(line, width)
            normalized = expand_tabs(line.to_s)
            return [''] if normalized.empty?
            return [normalized] if width.to_i <= 0

            wrapped = []
            current_line = +''
            current_width = 0

            width_i = width.to_i

            normalized.split(/\s+/).each do |word|
              next if word.nil? || word.empty?

              word_width = visible_length(word)

              if current_width.zero?
                current_line.replace(word)
                current_width = word_width
              elsif current_width + 1 + word_width <= width_i
                current_line << ' ' unless current_line.empty?
                current_line << word
                current_width += 1 + word_width
              else
                wrapped << current_line.dup unless current_line.empty?
                current_line.replace(word)
                current_width = word_width
              end
            end

            wrapped << current_line.dup unless current_line.empty?
            wrapped = [''] if wrapped.empty?
            wrapped
          end

          def truncate_to(text, width, start_column: 0)
            max_width = width.to_i
            return '' if max_width <= 0

            str = text.to_s
            return '' if str.empty?

            # Fast-path: preserve original when it already fits and contains no tab/newline.
            if !(str.include?("\t") || str.include?("\n") || str.include?("\r")) && (max_width >= visible_length(str))
              return str
            end

            buffer = +''
            current_width = 0
            column = start_column.to_i

            str.scan(TOKEN_REGEX).each do |token|
              if token.start_with?("\e[")
                buffer << token
                next
              end

              next if token == "\e"

              remaining = max_width - current_width
              break if remaining <= 0

              case token
              when "\t"
                spaces = TAB_SIZE - (column % TAB_SIZE)
                take = [spaces, remaining].min
                buffer << (' ' * take)
                current_width += take
                column += take
              when "\n", "\r"
                # Never allow newlines to affect terminal layout; treat as a space.
                break if remaining < 1

                buffer << ' '
                current_width += 1
                column += 1
              else
                token_width = display_width_for(token)
                break if token_width > remaining

                buffer << token
                current_width += token_width
                column += token_width
              end
            end

            buffer
          end

          def pad_right(text, width, start_column: 0, pad: ' ')
            w = width.to_i
            return '' if w <= 0

            clipped = truncate_to(text.to_s, w, start_column: start_column)
            pad_len = w - visible_length(clipped)
            pad_len.positive? ? (clipped + (pad.to_s * pad_len)) : clipped
          end

          def pad_left(text, width, start_column: 0, pad: ' ')
            w = width.to_i
            return '' if w <= 0

            clipped = truncate_to(text.to_s, w, start_column: start_column)
            pad_len = w - visible_length(clipped)
            pad_len.positive? ? ((pad.to_s * pad_len) + clipped) : clipped
          end

          def pad_center(text, width, start_column: 0, pad: ' ')
            w = width.to_i
            return '' if w <= 0

            clipped = truncate_to(text.to_s, w, start_column: start_column)
            pad_len = w - visible_length(clipped)
            return clipped unless pad_len.positive?

            left = pad_len / 2
            right = pad_len - left
            (pad.to_s * left) + clipped + (pad.to_s * right)
          end

          # Wraps text by terminal cell width without splitting grapheme clusters.
          # Preserves newlines and expands tabs relative to the provided start column.
          #
          # This is intended for UI text entry/display helpers (notes, dialogs),
          # not for paragraph-aware ebook formatting.
          def wrap_cells(text, width, start_column: 0)
            w = width.to_i
            return [''] if w <= 0

            lines = []
            line = +''
            line_width = 0
            column = start_column.to_i

            text.to_s.each_grapheme_cluster do |cluster|
              if cluster == "\n"
                lines << line.dup
                line.clear
                line_width = 0
                column = start_column.to_i
                next
              end

              cluster = ' ' if cluster == "\r"

              if cluster == "\t"
                spaces = TAB_SIZE - (column % TAB_SIZE)
                spaces.times do
                  if line_width >= w
                    lines << line.dup
                    line.clear
                    line_width = 0
                    column = start_column.to_i
                  end
                  line << ' '
                  line_width += 1
                  column += 1
                end
                next
              end

              cw = display_width_for(cluster)
              next if cw <= 0
              next if cw > w

              if line_width.positive? && (line_width + cw > w)
                lines << line.dup
                line.clear
                line_width = 0
                column = start_column.to_i
              end

              break if cw > (w - line_width)

              line << cluster
              line_width += cw
              column += cw
            end

            lines << line.dup
            lines = [''] if lines.empty?
            lines
          end
        end
      end
    end
  end
end
