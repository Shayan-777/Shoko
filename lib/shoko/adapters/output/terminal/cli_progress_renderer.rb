# frozen_string_literal: true

require_relative 'terminal'
require_relative 'text_metrics'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Renders a simple two-line progress indicator in the CLI.
        class CLIProgressRenderer
          CLEAR_LINE = "\e[2K"
          CURSOR_UP = "\e[1A"

          def initialize(terminal_service:, output: $stdout, text_metrics: TextMetrics)
            @terminal_service = terminal_service
            @output = output
            @text_metrics = text_metrics
            @lines_drawn = 0
          end

          def render(message: nil, progress: 0.0)
            lines = build_lines(message, progress)
            redraw(lines)
          end

          def clear
            return if @lines_drawn <= 0

            @lines_drawn.times { @output.print(CURSOR_UP) }
            @lines_drawn.times { @output.print("\r#{CLEAR_LINE}\n") }
            @output.flush
            @lines_drawn = 0
          end

          private

          def redraw(lines)
            @lines_drawn.times { @output.print(CURSOR_UP) } if @lines_drawn.positive?

            lines.each do |line|
              @output.print("\r#{CLEAR_LINE}#{line}\n")
            end

            extra = @lines_drawn - lines.length
            extra.times { @output.print("\r#{CLEAR_LINE}\n") } if extra.positive?

            @output.flush
            @lines_drawn = lines.length
          end

          def build_lines(message, progress)
            width = terminal_width
            layout = layout_for(width)
            indent = layout[:indent]
            content_width = layout[:content_width]

            lines = []
            message_text = message.to_s.strip
            unless message_text.empty?
              truncated = @text_metrics.truncate_to(message_text, content_width)
              lines << ((' ' * indent) + color_dim(truncated))
            end

            lines << ((' ' * indent) + build_bar(content_width, progress))
            lines
          end

          def terminal_width
            _h, w = @terminal_service.size
            w = w.to_i
            w.positive? ? w : 80
          end

          def layout_for(width)
            max_width = (width.to_i / 4.0).floor
            content_width = [max_width, 10].max
            { indent: 0, content_width: content_width }
          end

          def build_bar(width, progress)
            usable = [width.to_i, 10].max
            filled = (usable * progress.to_f.clamp(0.0, 1.0)).round
            accent = ansi::BRIGHT_GREEN
            dim = ansi::DIM
            reset = ansi::RESET

            bar = accent + ('━' * filled) + reset
            bar << dim << ('━' * (usable - filled)) << reset if filled < usable
            bar
          end

          def color_dim(text)
            ansi::DEFAULT_FG + ansi::DIM + text + ansi::RESET
          end

          def ansi
            Terminal::ANSI
          end
        end
      end
    end
  end
end
