# frozen_string_literal: true

require_relative '../adapters/output/terminal/terminal'
require_relative '../adapters/output/terminal/text_metrics'

module Shoko
  module Application
    # Presents progress updates for CLI-only (pre-TUI) book loading.
    class CLIProgressPresenter
      MIN_PROGRESS_DELTA = 0.01

      def initialize(terminal_service:, output: $stdout,
                     text_metrics: Shoko::Adapters::Output::Terminal::TextMetrics)
        @renderer = CLIProgressRenderer.new(
          terminal_service: terminal_service,
          output: output,
          text_metrics: text_metrics
        )
        @last_message = nil
        @last_progress = nil
      end

      def start(message: 'Preparing book...')
        @last_message = message
        @last_progress = 0.0
        @renderer.render(message: @last_message, progress: @last_progress)
      end

      def update_status(message: nil, progress: nil)
        updates = false

        if message && message != @last_message
          @last_message = message
          updates = true
        end

        unless progress.nil?
          normalized = progress.to_f.clamp(0.0, 1.0)
          if @last_progress.nil? || (normalized - @last_progress).abs >= MIN_PROGRESS_DELTA
            @last_progress = normalized
            updates = true
          end
        end

        return false unless updates

        @renderer.render(message: @last_message, progress: @last_progress)
        true
      end

      def finish
        @renderer.clear
      end
    end

    # Renders a simple two-line progress indicator in the CLI.
    class CLIProgressRenderer
      CLEAR_LINE = "\e[2K"
      CURSOR_UP = "\e[1A"

      def initialize(terminal_service:, output: $stdout,
                     text_metrics: Shoko::Adapters::Output::Terminal::TextMetrics)
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
        if @lines_drawn.positive?
          @lines_drawn.times { @output.print(CURSOR_UP) }
        end

        lines.each do |line|
          @output.print("\r#{CLEAR_LINE}#{line}\n")
        end

        extra = @lines_drawn - lines.length
        if extra.positive?
          extra.times { @output.print("\r#{CLEAR_LINE}\n") }
        end

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
          lines << (' ' * indent) + color_dim(truncated)
        end

        lines << (' ' * indent) + build_bar(content_width, progress)
        lines
      end

      def terminal_width
        _h, w = @terminal_service.size
        w = w.to_i
        w.positive? ? w : 80
      rescue StandardError
        80
      end

      def layout_for(width)
        max_width = (width.to_i / 4.0).floor
        content_width = [max_width, 10].max
        { indent: 0, content_width: content_width }
      end

      def build_bar(width, progress)
        usable = [width.to_i, 10].max
        filled = (usable * progress.to_f.clamp(0.0, 1.0)).round
        accent = terminal_ansi::BRIGHT_GREEN
        dim = terminal_ansi::DIM
        reset = terminal_ansi::RESET

        bar = accent + ('━' * filled) + reset
        if filled < usable
          bar << dim << ('━' * (usable - filled)) << reset
        end
        bar
      end

      def color_dim(text)
        terminal_ansi::DEFAULT_FG + terminal_ansi::DIM + text + terminal_ansi::RESET
      end

      def terminal_ansi
        Shoko::Adapters::Output::Terminal::Terminal::ANSI
      end
    end
  end
end
