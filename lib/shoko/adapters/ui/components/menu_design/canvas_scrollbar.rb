# frozen_string_literal: true

require_relative '../status_bar/palette'
require_relative '../ui/list_windowing'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # The canvas family's slim right-edge scrollbar: a lighter track with
          # a brand-blue thumb, occupying the last column of the content
          # measure.
          #
          # Drawn by anything scrollable on the canvas — the selectable list and
          # the RSS reading pane — so the bar looks and behaves identically
          # wherever it appears, and its geometry is computed in one place.
          module CanvasScrollbar
            Palette = StatusBar::Palette

            GLYPH = '█'
            WIDTH = 1

            module_function

            # @param top [Integer] first content row of the scrollable area
            # @param height [Integer] rows the area occupies
            # @param total [Integer] scrollable items (or lines) in total
            # @param visible [Integer] items shown at once
            # @param offset [Integer] index of the first visible item
            def render(surface:, bounds:, frame:, top:, height:, total:, visible:, offset:)
              return unless visible?(total: total, visible: visible, height: height)

              thumb = Ui::ListWindowing.scrollbar_thumb(total: total, visible: visible, scroll: offset,
                                                        track_rows: height)
              col = frame.content_x + frame.content_width - WIDTH
              height.times do |index|
                surface.write(bounds, top + index, col, frame.seg(GLYPH, thumb_colour(thumb, index)))
              end
            end

            # There is nothing to indicate when everything already fits.
            def visible?(total:, visible:, height:)
              total > visible && height.positive?
            end

            def thumb_colour(thumb, index)
              within = index >= thumb[:start] && index < thumb[:start] + thumb[:size]
              within ? Palette::LIST_SCROLL_THUMB_FG : Palette::LIST_SCROLL_TRACK_FG
            end
          end
        end
      end
    end
  end
end
