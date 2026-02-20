# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
    module Sidebar
      # Renders a scrollbar at the right edge of the TOC content area.
      class ScrollbarRenderer
        include Adapters::Ui::Constants::Ui

        TRACK_CHAR = '░'
        THUMB_CHAR = '█'

        def initialize(context)
          @context = context
        end

        def render
          metrics = @context.scroll_metrics
          return unless metrics.scrollable?

          draw_track(metrics)
          draw_thumb(metrics)
        end

        private

        def draw_track(metrics)
          track_end = metrics.track_start_y + metrics.track_height - 1
          line = "#{COLOR_TEXT_DIM}#{TRACK_CHAR * SCROLLBAR_WIDTH}#{Shoko::Shared::Terminal::Ansi::RESET}"
          metrics.track_start_y.upto(track_end) do |row|
            @context.write(row, metrics.scrollbar_start_col, line)
          end
        end

        def draw_thumb(metrics)
          return unless metrics.thumb_height.positive?

          thumb_end = metrics.thumb_start_y + metrics.thumb_height - 1
          line = "#{COLOR_TEXT_ACCENT}#{THUMB_CHAR * SCROLLBAR_WIDTH}#{Shoko::Shared::Terminal::Ansi::RESET}"
          metrics.thumb_start_y.upto(thumb_end) do |row|
            @context.write(row, metrics.scrollbar_start_col, line)
          end
        end
      end
    end
  end
end
