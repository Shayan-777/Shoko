# frozen_string_literal: true

require_relative '../../ui/text_utils'
require_relative '../../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Body rendering helpers for the translator screen.
          module TranslatorScreenComponentBodySupport
            private

            def body_lines(box, kind)
              height = body_height(box, kind)
              width = body_width(box)
              if body_text(kind).empty?
                return empty_source_lines(width, height) if kind == :source && show_input_cursor?

                return placeholder_lines(kind, width, height)
              end

              padded_lines(wrapped_body_lines(kind, width).first(height), width, height)
            end

            def wrapped_body_lines(kind, width)
              return source_body_lines(width) if kind == :source

              colorize_lines(wrap_text(body_text(kind), width))
            end

            def body_text(kind)
              kind == :source ? translator_input_text : translator_output_text
            end

            def source_body_lines(width)
              lines = wrap_text(translator_input_text, width).dup
              return colorize_lines(lines) unless show_input_cursor?

              cursor_line, cursor_column = cursor_position(width)
              lines << '' while lines.length <= cursor_line
              lines[cursor_line] = apply_cursor_highlight(lines[cursor_line], cursor_column)
              colorize_lines(lines)
            end

            def empty_source_lines(width, height)
              padded_lines([cursor_placeholder_line(width)].first(height), width, height)
            end

            def placeholder_lines(kind, width, height)
              text = kind == :source ? 'Type or paste text here.' : output_placeholder
              lines = [style_placeholder_line(text, width)]
              lines + Array.new([height - lines.length, 0].max) { empty_body_line(width) }
            end

            def output_placeholder
              translator_status == :error ? status_message : 'Translation appears here.'
            end

            def padded_lines(lines, width, height)
              padded = Array(lines).map { |line| pad_body_line(line, width) }
              padded + Array.new([height - padded.length, 0].max) { empty_body_line(width) }
            end

            def footer_text
              'Click the language bars to switch languages. Type on the left. Press Enter to translate.'
            end

            def status_message
              return translator_message unless translator_message.empty?

              translator_status == :error ? 'Translation failed.' : 'Choose languages, then type on the left.'
            end

            def colorize_lines(lines)
              Array(lines).map { |line| "#{panel_text_fg}#{line}#{reset}" }
            end

            def show_input_cursor?
              current_mode == :translator && translator_focus == :input
            end

            def cursor_placeholder_line(width)
              prompt_width = [width - 1, 1].max
              prompt = Shoko::Shared::Terminal::TextMetrics.truncate_to('Type or paste text here.', prompt_width)
              cursor = "#{cursor_bg}#{cursor_fg} #{reset}#{panel_muted_fg}"
              "#{cursor}#{prompt}#{reset}"
            end

            def style_placeholder_line(text, width)
              content = Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, width)
              "#{panel_muted_fg}#{content}#{reset}"
            end

            def cursor_position(width)
              cursor = translator_input_cursor.clamp(0, translator_input_text.length)
              prefix_lines = wrap_text(translator_input_text[0, cursor], width)
              line_index = [prefix_lines.length - 1, 0].max
              column = visible_length(prefix_lines.last.to_s)
              return [line_index + 1, 0] if column >= width

              [line_index, column]
            end

            def apply_cursor_highlight(line, column)
              before, current, after = split_line_at_column(line, column)
              current_cell = current.to_s.empty? ? ' ' : current.to_s
              highlighted = "#{cursor_bg}#{cursor_fg}#{current_cell}#{reset}#{panel_text_fg}"
              "#{before}#{highlighted}#{after}"
            end

            def split_line_at_column(line, column)
              before = +''
              after = +''
              current = nil
              visible = 0
              line.to_s.each_grapheme_cluster do |cluster|
                if current
                  after << cluster
                elsif visible >= column
                  current = cluster
                else
                  before << cluster
                  visible += Shoko::Shared::Terminal::TextMetrics.display_width_for(cluster)
                end
              end
              [before, current, after]
            end

            def visible_length(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end
          end
        end
      end
    end
  end
end
