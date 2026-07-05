# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative '../status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # A raised card on the canvas — the family's "well" surface (the
          # tone the translator's compose editor sits on). Menu views use it
          # for inspector/detail panes: one elevation step above the canvas,
          # separated purely by its background, with an optional accent title
          # on its first row and one column of inner padding.
          class CanvasWell
            Palette = StatusBar::Palette
            TextMetrics = Shoko::Shared::Terminal::TextMetrics

            PAD = 1

            # +rect+ is bounds-relative: x/y are 1-based columns/rows inside
            # the component's bounds, like every Surface write.
            def initialize(surface, bounds, rect:)
              @surface = surface
              @bounds = bounds
              @rect = rect
            end

            def paint(title: nil, accent: nil)
              blank = "#{Palette::RESET}#{Palette::TRANS_FIELD_BG}#{' ' * @rect.width}#{Palette::RESET}"
              @rect.height.times { |offset| @surface.write(@bounds, @rect.y + offset, @rect.x, blank) }
              render_title(title, accent) if title && !title.to_s.empty?
            end

            def inner_width
              [@rect.width - (PAD * 2), 1].max
            end

            # Rows available under the title row.
            def inner_height
              [@rect.height - 2, 0].max
            end

            def inner_top
              @rect.y + 2
            end

            # Write one padded line at +offset+ under the title row; +segments+
            # are [text, fg] pairs resolved over the well surface.
            def write_line(offset, segments)
              row = inner_top + offset
              return if row >= @rect.y + @rect.height

              line = Array(segments).map { |text, foreground| seg(text, foreground) }.join
              @surface.write(@bounds, row, @rect.x + PAD, "#{line}#{Palette::RESET}")
            end

            def seg(text, foreground)
              "#{Palette::RESET}#{Palette::TRANS_FIELD_BG}#{foreground || Palette::LANDING_TEXT_FG}#{text}"
            end

            def truncate(text, width = inner_width)
              TextMetrics.truncate_to(text.to_s, [width, 0].max)
            end

            private

            def render_title(title, accent)
              clipped = truncate(title)
              @surface.write(
                @bounds, @rect.y, @rect.x + PAD,
                "#{seg(clipped, "#{Palette::BOLD}#{accent || Palette::LANDING_TEXT_FG}")}#{Palette::RESET}"
              )
            end
          end
        end
      end
    end
  end
end
