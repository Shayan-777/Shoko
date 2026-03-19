# frozen_string_literal: true

require_relative '../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module DictionaryPopup
          # Text/layout helpers for dictionary popup setup mode.
          module SetupTextSupport
            include Adapters::Ui::Constants::Ui

            private

            def divider_line(width)
              style_text('─' * width, color: COLOR_TEXT_DIM)
            end

            def align_left_right(left, right, width)
              left_len = visible_length(left)
              right_len = visible_length(right)
              padding = width - left_len - right_len
              return "#{left}#{' ' * padding}#{right}" if padding >= 1

              truncated_left = truncate_visible(left, [width - right_len - 1, 1].max)
              gap = [width - visible_length(truncated_left) - right_len, 1].max
              "#{truncated_left}#{' ' * gap}#{right}"
            end

            def truncate_visible(text, width)
              Shared::Terminal::TextMetrics.truncate_to(text.to_s, width.to_i)
            rescue Shoko::Error
              Ui::TextUtils.truncate_text(text.to_s.gsub(/\e\[[0-9;]*m/, ''), width)
            end

            def language_chip(value, active:)
              lang = value.to_s.strip
              label = lang.empty? ? '--' : lang.upcase
              color = if lang.empty?
                        COLOR_TEXT_DIM
                      elsif active
                        COLOR_TEXT_ACCENT
                      else
                        COLOR_TEXT_PRIMARY
                      end
              style_text("[#{label}]", color: color, bold: active && !lang.empty?)
            end

            def pack_inline_segments(segments, width, gap: '  ')
              out = []
              current = ''
              Array(segments).each do |segment|
                next if segment.to_s.empty?

                candidate = current.empty? ? segment.to_s : "#{current}#{gap}#{segment}"
                if visible_length(candidate) <= width
                  current = candidate
                else
                  out << current unless current.empty?
                  current = segment.to_s
                end
              end
              out << current unless current.empty?
              out
            end

            def wrap_plain(text, width)
              text.to_s.split("\n").flat_map { |line| wrap_line(line, width) }
            end

            def wrap_line(text, width)
              return [''] if text.nil?
              return [text.to_s] if visible_length(text) <= width

              words = text.to_s.split(/\s+/)
              lines = []
              current = ''
              words.each do |word|
                current = append_wrapped_word(lines, current, word, width)
              end
              lines << current unless current.empty?
              lines
            end

            def append_wrapped_word(lines, current, word, width)
              return word if current.empty?

              candidate = "#{current} #{word}"
              return candidate if visible_length(candidate) <= width

              lines << current
              word
            end

            def setup_render_context(layout)
              padding_h = self.class::PADDING_H
              padding_v = self.class::PADDING_V
              width = [layout.width - (padding_h * 2), 10].max
              height = [layout.height - (padding_v * 2) - 1, 1].max
              @last_content_height = height
              {
                x: layout.origin_x + padding_h,
                y: layout.origin_y + padding_v,
                width: width,
                height: height,
              }
            end

            def render_setup_content_lines(surface, bounds, context, lines)
              visible_lines = lines.first(context[:height])
              visible_lines.each_with_index do |line, idx|
                row = context[:y] + idx
                surface.write(bounds, row, context[:x], pad_line(line.to_s, context[:width]))
              end
            end

            def render_setup_empty_lines(surface, bounds, context, rendered_count)
              remaining = [context[:height] - rendered_count, 0].max
              empty_line = pad_line('', context[:width])
              remaining.times do |idx|
                row = context[:y] + rendered_count + idx
                surface.write(bounds, row, context[:x], empty_line)
              end
            end
          end
        end
      end
    end
  end
end
