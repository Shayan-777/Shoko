# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Shared text layout utilities for terminal UI rendering.
          module TextUtils
            module_function

            def wrap_text(text, width)
              t = (text || '').to_s
              w = width.to_i
              return [''] if t.empty?
              return [''] if w <= 0

              Shoko::Shared::Terminal::TextMetrics.wrap_cells(t, w)
            end

            # Word-aware wrapping for prose (descriptions, notes, articles):
            # lines break between words; a single word longer than the line
            # falls back to cell wrapping so nothing is ever lost.
            def wrap_words(text, width)
              w = width.to_i
              metrics = Shoko::Shared::Terminal::TextMetrics
              words = (text || '').to_s.split(/\s+/).reject(&:empty?)
              return [''] if words.empty? || w <= 0

              lines = [+'']
              words.each do |word|
                segments = metrics.visible_length(word) > w ? metrics.wrap_cells(word, w) : [word]
                segments.each { |segment| flow_segment(lines, segment, w) }
              end
              lines
            end

            def flow_segment(lines, segment, width)
              candidate = lines.last.empty? ? segment : "#{lines.last} #{segment}"
              if Shoko::Shared::Terminal::TextMetrics.visible_length(candidate) <= width
                lines[-1] = candidate
              else
                lines << segment.dup
              end
            end

            # Word-wrap plain prose into display-width-safe lines, preserving hard
            # newlines: each "\n" forces a new row, blank lines survive as ''.
            # Words longer than the line fall back to cell wrapping (via
            # #wrap_words), so nothing ever overflows the width.
            def wrap_prose(text, width)
              text.to_s.split("\n").flat_map { |paragraph| wrap_words(paragraph, width) }
            end

            # Wrap editor text for caret mapping: every character is preserved (a
            # break space rides the end of its line), each "\n" forces a new row
            # and is consumed as the break, and each row records the character
            # index where it starts so a flat caret index maps onto a
            # (row, column). Rows break on display width, so wide (CJK) input
            # never overflows the field. Returns [{ text:, start: }].
            def wrap_indexed(text, width)
              w = [width.to_i, 1].max
              source = text.to_s
              rows = []
              index = 0
              loop do
                newline = source.index("\n", index)
                line_end = newline || source.length
                wrap_indexed_segment(rows, source, index, line_end, w)
                break unless newline

                index = newline + 1
              end
              rows
            end

            # Wrap one physical line [start, line_end) into rows; always adds at
            # least one row (empty for a blank line).
            def wrap_indexed_segment(rows, text, start, line_end, width)
              if start == line_end
                rows << { text: '', start: start }
                return
              end

              cursor = start
              cursor = append_indexed_row(rows, text, cursor, width, line_end) while cursor < line_end
            end

            def append_indexed_row(rows, text, cursor, width, line_end)
              take = indexed_row_capacity(text, cursor, width, line_end)
              if cursor + take >= line_end
                rows << { text: text[cursor...line_end], start: cursor }
                return line_end
              end

              brk = text[cursor, take].rindex(' ')
              take = brk + 1 if brk&.positive?
              rows << { text: text[cursor, take], start: cursor }
              cursor + take
            end

            # Characters from +cursor+ that fit in +width+ display cells (at
            # least one, so a too-narrow field still makes progress).
            def indexed_row_capacity(text, cursor, width, line_end)
              metrics = Shoko::Shared::Terminal::TextMetrics
              taken = 0
              cells = 0
              text[cursor...line_end].each_char do |char|
                char_cells = metrics.visible_length(char)
                break if taken.positive? && cells + char_cells > width

                taken += 1
                cells += char_cells
                break if cells >= width
              end
              [taken, 1].max
            end

            def truncate_text(text, max_length)
              str = (text || '').to_s
              w = max_length.to_i
              return '' if w <= 0

              return str if Shoko::Shared::Terminal::TextMetrics.visible_length(str) <= w

              ellipsis = '...'
              ellipsis_w = Shoko::Shared::Terminal::TextMetrics.visible_length(ellipsis)
              return Shoko::Shared::Terminal::TextMetrics.truncate_to(str, w) if ellipsis_w >= w

              base = Shoko::Shared::Terminal::TextMetrics.truncate_to(str, w - ellipsis_w)
              base + ellipsis
            end

            def pad_right(text, width, pad: ' ')
              Shoko::Shared::Terminal::TextMetrics.pad_right(text.to_s, width.to_i, pad: pad)
            end

            def pad_left(text, width, pad: ' ')
              Shoko::Shared::Terminal::TextMetrics.pad_left(text.to_s, width.to_i, pad: pad)
            end
          end
        end
      end
    end
  end
end
