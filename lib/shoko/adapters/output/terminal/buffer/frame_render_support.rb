# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalBuffer
          class Frame
            # Row rendering and style-run flushing for terminal frame buffers.
            module FrameRenderSupport
              def rendered_rows
                (0...@height).map { |row_i| render_row(row_i) }
              end

              private

              def render_row(row_i)
                chars = @chars[row_i]
                styles = @styles[row_i]
                last_col = last_non_blank_col(chars, styles)
                return '' if last_col.negative?

                build_rendered_row(chars, styles, last_col)
              end

              def build_rendered_row(chars, styles, last_col)
                out, run, active_style = render_row_state
                col = 0

                while col <= last_col
                  col, active_style, run = append_rendered_cell(
                    chars,
                    styles,
                    col,
                    out: out,
                    run: run,
                    active_style: active_style
                  )
                end

                flush_run(out, run, active_style)
                out
              end

              def render_row_state
                [+'', +'', nil]
              end

              def append_rendered_cell(chars, styles, col, out:, run:, active_style:)
                char = chars[col]
                return [col + 1, active_style, run] if char == CONTINUATION

                style = normalized_style(styles[col])
                if style != active_style
                  flush_run(out, run, active_style)
                  run = +''
                  active_style = style
                end

                run << (char || ' ')
                [col + 1, active_style, run]
              end

              def normalized_style(style)
                return nil if style.nil? || style.empty?

                style
              end

              def last_non_blank_col(chars, styles)
                idx = chars.length - 1
                while idx >= 0
                  char = chars[idx]
                  style = styles[idx]
                  return idx if renderable_cell?(char, style)

                  idx -= 1
                end
                -1
              end

              def renderable_cell?(char, style)
                return true if char == CONTINUATION
                return true if style && !style.empty?

                char && char != ' '
              end

              def flush_run(out, run, style)
                return if run.empty?

                if style
                  out << style << run << TerminalOutput::ANSI::RESET
                else
                  out << run
                end
              end
            end
          end
        end
      end
    end
  end
end
