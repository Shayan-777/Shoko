# frozen_string_literal: true

require_relative '../status_bar/palette'
require_relative 'icon_set'
require_relative 'canvas_frame'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Selectable rows on the canvas surface, in the family's selection
          # language: the selected entry takes the highlighted-row strip and
          # the brand-blue pointer, the pointer-hovered entry takes the softer
          # hover tone, everything else rests on the canvas. Rows register
          # their geometry with the menu hit registry as they render, so the
          # same code that draws a row makes it clickable.
          #
          # The scrollbar owns the last column of the content measure and rows
          # stop one column short of it, so a row's background — and its click
          # target — never runs under the bar; RIGHT_GAP holds the text itself
          # further clear, the way the in-book search list does.
          class CanvasList
            Palette = StatusBar::Palette

            SCROLL_GLYPH = '█'
            SCROLLBAR_WIDTH = 1
            RIGHT_GAP = 2 # blank columns between a row's text and the scrollbar

            def initialize(surface, bounds, frame:, hits: nil)
              @surface = surface
              @bounds = bounds
              @frame = frame
              @hits = hits
            end

            # Columns a row's own text may fill, once the pointer column, the
            # scrollbar and its gap are taken out. Callers that wrap their own
            # text (rather than letting it truncate) measure against this.
            def text_width(width = nil)
              [strip_width(width) - RIGHT_GAP - @frame.width_of(IconSet.selection_pointer), 1].max
            end

            # A single-row entry. +left+/+right+ are [text, fg] segment lists;
            # +action+ makes the row clickable (and hover-lit under the
            # pointer); +width+ narrows the strip when a well sits beside it.
            def row(row:, left:, right: [], selected: false, action: nil, width: nil)
              strip = strip_width(width)
              background = row_background(selected, hover_row?(row, 1, action, strip))
              line = @frame.compose(
                left: [pointer_segment(selected), *left],
                right: right,
                background: background,
                width: strip,
                reserve: RIGHT_GAP
              )
              @surface.write(@bounds, row, @frame.content_x, line)
              register(row: row, height: 1, action: action, width: strip)
            end

            # A multi-row entry (search-result-style block): every row shares
            # the entry's background; the pointer rides the first row.
            def block(row:, lines:, selected: false, action: nil, width: nil)
              strip = strip_width(width)
              background = row_background(selected, hover_row?(row, lines.length, action, strip))
              lines.each_with_index do |line, offset|
                segments = [pointer_segment(selected && offset.zero?), *line[:left]]
                composed = @frame.compose(left: segments, right: line[:right] || [], background: background,
                                          width: strip, reserve: RIGHT_GAP)
                @surface.write(@bounds, row + offset, @frame.content_x, composed)
              end
              register(row: row, height: lines.length, action: action, width: strip)
            end

            # One region for the whole list body, so wheel turns anywhere over
            # it move the selection.
            def register_wheel(top:, height:, action:)
              return unless @hits && height.positive?

              @hits.register(
                col: @bounds.x, row: @bounds.y + top - 1,
                width: @bounds.width, height: height,
                action: action
              )
            end

            # Slim right-edge scrollbar: lighter track, brand-blue thumb —
            # the search list's signature, on the canvas surface.
            def render_scrollbar(top:, height:, total:, visible:, offset:)
              return if total <= visible || height <= 0

              thumb = thumb_metrics(height, total, visible, offset)
              col = @frame.content_x + @frame.content_width - 1
              height.times do |index|
                in_thumb = index >= thumb[:start] && index < thumb[:start] + thumb[:size]
                color = in_thumb ? Palette::LIST_SCROLL_THUMB_FG : Palette::LIST_SCROLL_TRACK_FG
                @surface.write(@bounds, top + index, col, @frame.seg(SCROLL_GLYPH, color))
              end
            end

            private

            # A row's strip: the content measure, less the column the
            # scrollbar reserves at its right edge.
            def strip_width(width)
              [(width || @frame.content_width) - SCROLLBAR_WIDTH, 0].max
            end

            def thumb_metrics(height, total, visible, offset)
              size = (visible.to_f / total * height).round.clamp(1, height)
              room = height - size
              denom = [total - visible, 1].max
              start = room <= 0 ? 0 : ((offset.to_f / denom) * room).round.clamp(0, room)
              { size: size, start: start }
            end

            def pointer_segment(selected)
              pointer = IconSet.selection_pointer
              return [' ' * @frame.width_of(pointer), nil] unless selected

              [pointer, Palette::LANDING_POINTER_FG]
            end

            def row_background(selected, hovered)
              return Palette::LANDING_SELECTED_BG if selected
              return Palette::LIST_HOVER_BG if hovered

              Palette::LANDING_CANVAS_BG
            end

            def hover_row?(row, height, action, width)
              return false unless @hits && action

              @hits.hover?(
                col: @bounds.x + @frame.content_x - 1,
                row: @bounds.y + row - 1,
                width: width,
                height: height
              )
            end

            def register(row:, height:, action:, width:)
              return unless @hits && action

              @hits.register(
                col: @bounds.x + @frame.content_x - 1,
                row: @bounds.y + row - 1,
                width: width,
                height: height,
                action: action
              )
            end
          end
        end
      end
    end
  end
end
