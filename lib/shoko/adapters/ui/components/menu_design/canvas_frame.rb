# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative '../status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # The shared frame every menu view renders inside: the full-bleed
          # elevated slate canvas of the bar-anchored family, a hairline rule
          # with the accent-colored view title riding it and the meta tucked
          # against the right end, and a dim hint resting on the bottom row.
          # Body content flows between them on the same surface — no boxes,
          # no divider lines; the surface itself is the frame.
          class CanvasFrame
            Palette = StatusBar::Palette
            TextMetrics = Shoko::Shared::Terminal::TextMetrics

            RULE_ROW = 2
            BODY_TOP = 4
            LEFT_INSET = 3
            RIGHT_INSET = 2
            MIN_SEGMENT_GAP = 2
            MAX_CONTENT_WIDTH = 100

            def initialize(surface, bounds)
              @surface = surface
              @bounds = bounds
            end

            attr_reader :bounds

            def paint
              blank = "#{Palette::RESET}#{Palette::LANDING_CANVAS_BG}#{' ' * @bounds.width}#{Palette::RESET}"
              (1..@bounds.height).each { |row| @surface.write(@bounds, row, 1, blank) }
            end

            def content_x
              1 + LEFT_INSET
            end

            def content_width
              [@bounds.width - LEFT_INSET - RIGHT_INSET, MAX_CONTENT_WIDTH].min
            end

            def body_top
              BODY_TOP
            end

            def body_bottom
              @bounds.height - 2
            end

            def body_height
              [body_bottom - body_top + 1, 0].max
            end

            # "── Title ········· meta ──", the dictionary card's rule shape.
            def render_rule(title:, accent:, meta: '')
              clipped_title, meta_part, fill = rule_layout(title, meta)
              rule = seg('── ', Palette::LANDING_RULE_FG) +
                     seg(clipped_title, "#{Palette::BOLD}#{accent}") +
                     seg(" #{'·' * fill}", Palette::LANDING_RULE_FG) +
                     seg(meta_part, Palette::LANDING_DIM_FG) +
                     seg(' ──', Palette::LANDING_RULE_FG)
              @surface.write(@bounds, RULE_ROW, content_x, "#{rule}#{Palette::RESET}")
            end

            def render_hint(text)
              value = text.to_s
              return if value.empty? || @bounds.height < BODY_TOP + 2

              @surface.write(@bounds, @bounds.height, content_x,
                             "#{seg(truncate(value, content_width), Palette::LANDING_DIM_FG)}#{Palette::RESET}")
            end

            # A left/right status pair on an arbitrary body row (scan progress,
            # result counts, sync state) in the same measure as the rule.
            def render_status(row:, left:, right: '', left_fg: nil, right_fg: nil)
              line = compose(
                left: [[left.to_s, left_fg || Palette::LANDING_DIM_FG]],
                right: right.to_s.empty? ? [] : [[right.to_s, right_fg || Palette::LANDING_DIM_FG]]
              )
              @surface.write(@bounds, row, content_x, line)
            end

            def write_line(row, segments)
              @surface.write(@bounds, row, content_x, compose(left: segments, right: []))
            end

            # Left segments flow, right segments snap to the content's right
            # edge; the left side truncates first so the right cluster (sizes,
            # counts, ages) always survives. +reserve+ holds that many trailing
            # columns clear of text — still background-filled, so the strip
            # reads as one surface — which is how a row keeps its width while
            # leaving air beside a scrollbar. Every span sits on the canvas.
            def compose(left:, right: [], background: nil, width: content_width, reserve: 0)
              bg = background || Palette::LANDING_CANVAS_BG
              inner = [width - reserve, 0].max
              trailing = [width - inner, 0].max
              pad = trailing.positive? ? seg(' ' * trailing, nil, background: bg) : ''
              "#{compose_inner(left, right, inner, bg)}#{pad}#{Palette::RESET}"
            end

            def seg(text, foreground, background: nil)
              bg = background || Palette::LANDING_CANVAS_BG
              "#{Palette::RESET}#{bg}#{foreground || Palette::LANDING_TEXT_FG}#{text}"
            end

            def truncate(text, width)
              TextMetrics.truncate_to(text.to_s, [width, 0].max)
            end

            def width_of(text)
              TextMetrics.visible_length(text.to_s)
            end

            private

            def rule_layout(title, meta)
              clipped_title = truncate(title.to_s, [content_width - 14, 4].max)
              clipped_meta = truncate(meta.to_s, [content_width - width_of(clipped_title) - 12, 0].max)
              meta_part = clipped_meta.empty? ? '' : " #{clipped_meta}"
              fill = [content_width - width_of("── #{clipped_title} #{meta_part} ──"), 1].max
              [clipped_title, meta_part, fill]
            end

            # The left/right pair laid down across +inner+ columns. The right
            # cluster is measured first and clipped to the room it actually
            # has, so an over-wide label can never spill past the strip.
            def compose_inner(left, right, inner, background)
              right_width = [segments_width(right), inner].min
              budget = [inner - right_width - (right_width.positive? ? MIN_SEGMENT_GAP : 0), 0].max
              left_text, left_width = compose_segments(left, budget, background)
              right_text, right_drawn = compose_segments(right, right_width, background)
              gap = [inner - left_width - right_drawn, 0].max
              "#{left_text}#{seg(' ' * gap, nil, background: background)}#{right_text}"
            end

            def compose_segments(segments, budget, background)
              remaining = budget
              styled = Array(segments).map do |text, foreground|
                cell = truncate(text.to_s, remaining)
                remaining -= width_of(cell)
                seg(cell, foreground, background: background)
              end
              [styled.join, budget - remaining]
            end

            def segments_width(segments)
              Array(segments).sum { |text, _fg| width_of(text.to_s) }
            end
          end
        end
      end
    end
  end
end
