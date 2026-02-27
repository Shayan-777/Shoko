# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Simple progress/loading overlay rendered as a component.
          # Draws a single-row progress bar; expects progress in state at [:ui, :loading_progress].
          class LoadingOverlayComponent < BaseComponent
            include Adapters::Ui::Constants::Ui

            def initialize(ui_state_reader:)
              super()
              @ui_state_reader = ui_state_reader
            end

            def do_render(surface, bounds)
              width  = bounds.width
              height = bounds.height

              message = ui_state_reader&.loading_message.to_s.strip

              message_row = 1
              bar_row = message.empty? ? 2 : message_row + 2
              bar_row = [bar_row, height - 1].min
              bar_col = 2
              bar_width = (width - (bar_col + 1)).clamp(10, width - bar_col)

              progress = (ui_state_reader&.loading_progress || 0.0).to_f
              progress = progress.clamp(0.0, 1.0)
              filled = (bar_width * progress).round

              unless message.empty?
                label = Shoko::Shared::Terminal::TextMetrics.truncate_to(message, width - 2)
                label_col = [(width - Shoko::Shared::Terminal::TextMetrics.visible_length(label)) / 2, 1].max
                surface.write(bounds, message_row, label_col, "#{COLOR_TEXT_DIM}#{label}#{Shoko::Shared::Terminal::Ansi::RESET}")
              end

              track = if bar_width.positive?
                        (Shoko::Shared::Terminal::Ansi::BRIGHT_GREEN + ('━' * filled)) +
                          (Shoko::Shared::Terminal::Ansi::GRAY + ('━' * (bar_width - filled))) +
                          Shoko::Shared::Terminal::Ansi::RESET
                      else
                        ''
                      end
              surface.write(bounds, bar_row, bar_col, track)
            end

            private

            def ui_state_reader
              @ui_state_reader
            end
          end
        end
      end
    end
  end
end
