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
