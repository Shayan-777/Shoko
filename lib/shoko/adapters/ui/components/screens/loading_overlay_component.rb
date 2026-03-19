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

            OverlayLayout = Data.define(:message, :message_row, :bar_row, :bar_col, :bar_width, :progress)

            def initialize(ui_state_reader:)
              super()
              @ui_state_reader = ui_state_reader
            end

            def do_render(surface, bounds)
              layout = overlay_layout(bounds)
              write_message(surface, bounds, layout)
              surface.write(bounds, layout.bar_row, layout.bar_col, progress_track(layout))
            end

            private

            attr_reader :ui_state_reader

            def overlay_layout(bounds)
              message = loading_message
              message_row = 1
              bar_col = 2
              OverlayLayout.new(
                message: message,
                message_row: message_row,
                bar_row: [message.empty? ? 2 : message_row + 2, bounds.height - 1].min,
                bar_col: bar_col,
                bar_width: bar_width(bounds, bar_col),
                progress: loading_progress
              )
            end

            def write_message(surface, bounds, layout)
              return if layout.message.empty?

              label = Shoko::Shared::Terminal::TextMetrics.truncate_to(layout.message, bounds.width - 2)
              label_col = [(bounds.width - Shoko::Shared::Terminal::TextMetrics.visible_length(label)) / 2, 1].max
              surface.write(
                bounds,
                layout.message_row,
                label_col,
                "#{COLOR_TEXT_DIM}#{label}#{Shoko::Shared::Terminal::Ansi::RESET}"
              )
            end

            def progress_track(layout)
              return '' unless layout.bar_width.positive?

              filled = (layout.bar_width * layout.progress).round
              [
                Shoko::Shared::Terminal::Ansi::BRIGHT_GREEN,
                '━' * filled,
                Shoko::Shared::Terminal::Ansi::GRAY,
                '━' * (layout.bar_width - filled),
                Shoko::Shared::Terminal::Ansi::RESET,
              ].join
            end

            def loading_message
              ui_state_reader&.loading_message.to_s.strip
            end

            def loading_progress
              (ui_state_reader&.loading_progress || 0.0).to_f.clamp(0.0, 1.0)
            end

            def bar_width(bounds, bar_col)
              (bounds.width - (bar_col + 1)).clamp(10, bounds.width - bar_col)
            end
          end
        end
      end
    end
  end
end
