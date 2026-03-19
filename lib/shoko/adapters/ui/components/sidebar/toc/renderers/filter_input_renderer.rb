# frozen_string_literal: true

require_relative '../../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Sidebar
          # Renders filter input field.
          class FilterInputRenderer
            include Adapters::Ui::Constants::Ui

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
              prompt = "#{COLOR_TEXT_ACCENT}SEARCH ▸#{Shoko::Shared::Terminal::Ansi::RESET} "
              @context.write(start_y, x_pos, "#{prompt}#{styled_input_text}")
            end

            def write_help_text
              help = "#{COLOR_TEXT_DIM}ESC cancel#{Shoko::Shared::Terminal::Ansi::RESET}"
              @context.write(start_y + 1, x_pos, help)
            end

            def styled_input_text
              base = "#{COLOR_TEXT_PRIMARY}#{@context.filter_text}#{Shoko::Shared::Terminal::Ansi::RESET}"
              cursor = @context.filter_active? ? active_cursor : ''
              base + cursor
            end

            def active_cursor
              "#{Shoko::Shared::Terminal::Ansi::REVERSE} #{Shoko::Shared::Terminal::Ansi::RESET}"
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
  end
end
