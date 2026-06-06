# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative '../status_bar/palette'
require_relative 'snippet'

module Shoko
  module Adapters
    module Ui
      module Components
        module InBookSearch
          # Formats one in-book search result into its three styled rows:
          #   rows 1–2 — the context snippet (laid out by Snippet), match highlighted
          #   row 3    — location ("page P - ch. C - line L"), dimmed
          #
          # Pure presentation: owns no state beyond the result it wraps, so the
          # list component can keep to layout, scrolling, and the scrollbar.
          class ResultRow
            Palette = StatusBar::Palette
            SELECTED_MARK = '▋ ' # bar drawn down the whole left edge of the active entry

            def initialize(result)
              @result = result
            end

            # => [row1, row2, row3], each a styled string padded out to +width+.
            # The active entry carries the selection bar on all three rows.
            # +right_gap+ holds that many trailing columns clear of text (still
            # background-filled) — e.g. a blank column before the scrollbar.
            def render(width:, selected:, background:, right_gap: 0)
              text_width = [width - lead_width - right_gap, 4].max
              lead = mark_lead(selected, background)
              line1, line2 = snippet_rows(text_width, background)
              [
                compose(lead, line1, width, background),
                compose(lead, line2, width, background),
                compose(lead, location_segment(text_width, background), width, background),
              ]
            end

            private

            def lead_width
              visible_length(SELECTED_MARK)
            end

            # Lay [lead][body] down and pad with background out to +width+.
            def compose(lead, body, width, background)
              lead_text, lead_w = lead
              body_text, body_w = body
              gap = [width - lead_w - body_w, 0].max
              "#{lead_text}#{body_text}#{span(' ' * gap, Palette::LIST_DIM_FG, background)}#{Palette::RESET}"
            end

            # Selected entries get the accent bar; the rest are blank-indented so
            # every row's text still lines up at the same column.
            def mark_lead(selected, background)
              return [span(SELECTED_MARK, Palette::LIST_POINTER_FG, background), lead_width] if selected

              [span(' ' * lead_width, Palette::LIST_DIM_FG, background), lead_width]
            end

            # Rows 1–2: the context snippet, flowed and balanced across both lines.
            def snippet_rows(width, background)
              Snippet.new(**@result.slice(:before, :match, :after)).rows(width, background)
            end

            # Row 3: "page P - ch. C - line L", dimmed (page omitted when unknown).
            def location_segment(width, background)
              text = location_text(width)
              [span(text, Palette::LIST_DIM_FG, background), visible_length(text)]
            end

            def location_text(width)
              parts = []
              page = @result[:page_index]
              parts << "page #{page.to_i + 1}" unless page.nil?
              parts << "ch. #{@result[:chapter_index].to_i + 1}"
              # Prefer the line's position within its page; fall back to the
              # chapter-absolute line when not paginated.
              line = @result[:page_line_index] || @result[:line_index]
              parts << "line #{line.to_i + 1}"
              truncate(parts.join(' - '), width)
            end

            def span(text, foreground, background)
              "#{Palette::RESET}#{background}#{foreground}#{text}"
            end

            def visible_length(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end

            def truncate(text, width)
              Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, [width.to_i, 0].max)
            end
          end
        end
      end
    end
  end
end
