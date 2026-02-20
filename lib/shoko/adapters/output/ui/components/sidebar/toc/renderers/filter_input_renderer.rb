# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Renders filter input field.
      class FilterInputRenderer
        include Adapters::Output::Ui::Constants::Ui

        def initialize(context)
          @context = context
        end

        def render
          write_input_line
          write_help_text
          start_y + 2
        end

        private

        def write_input_line
          prompt = "#{COLOR_TEXT_ACCENT}SEARCH ▸#{Terminal::ANSI::RESET} "
          @context.write(start_y, x_pos, "#{prompt}#{styled_input_text}")
        end

        def write_help_text
          help = "#{COLOR_TEXT_DIM}ESC cancel#{Terminal::ANSI::RESET}"
          @context.write(start_y + 1, x_pos, help)
        end

        def styled_input_text
          base = "#{COLOR_TEXT_PRIMARY}#{@context.filter_text}#{Terminal::ANSI::RESET}"
          cursor = @context.filter_active? ? "#{Terminal::ANSI::REVERSE} #{Terminal::ANSI::RESET}" : ''
          base + cursor
        end

        def start_y
          @context.metrics.y + 2
        end

        def x_pos
          @context.metrics.x + 1
        end
      end
    end
  end
end
