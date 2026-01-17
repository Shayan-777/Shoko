# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Simple progress/loading overlay rendered as a component.
      # Draws a single-row progress bar; expects progress in state at [:ui, :loading_progress].
      class LoadingOverlayComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI

        def do_render(surface, bounds)
          width  = bounds.width
          height = bounds.height

          state = @dependencies.resolve(:global_state)
          message = state.get(%i[ui loading_message]).to_s.strip

          message_row = 1
          bar_row = message.empty? ? 2 : message_row + 2
          bar_row = [bar_row, height - 1].min
          bar_col = 2
          bar_width = (width - (bar_col + 1)).clamp(10, width - bar_col)

          progress = (state.get(%i[ui loading_progress]) || 0.0).to_f
          progress = progress.clamp(0.0, 1.0)
          filled = (bar_width * progress).round

          unless message.empty?
            label = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(message, width - 2)
            label_col = [(width - Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(label)) / 2, 1].max
            surface.write(bounds, message_row, label_col, "#{COLOR_TEXT_DIM}#{label}#{Terminal::ANSI::RESET}")
          end

          track = if bar_width.positive?
                    (Terminal::ANSI::BRIGHT_GREEN + ('━' * filled)) +
                      (Terminal::ANSI::GRAY + ('━' * (bar_width - filled))) +
                      Terminal::ANSI::RESET
                  else
                    ''
                  end
          surface.write(bounds, bar_row, bar_col, track)
        end
      end
    end
  end
end
