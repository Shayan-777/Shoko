# frozen_string_literal: true

require_relative 'base_component'
require_relative 'bottom_left_panel'
require_relative 'overlay_mouse_target'
require_relative 'ui/panel_spans'
require_relative 'ui/list_helpers'
require_relative 'in_book_search/result_row'
require 'shoko/shared/terminal/text_metrics'
require_relative 'status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        # In-book search results, rendered as an upward list docked directly onto
        # the bottom status bar (which hosts the "Search/<format>" input). The list
        # snaps flush to the left edge and the bar — no floating gap — while keeping
        # a capped width on the right, and grows upward from the bar: the first/best
        # match sits closest to the input, with further matches stacked above it.
        #
        # Each result is a roomy three-row block — two rows of snippet (the leading
        # context plus the highlighted match, then the trailing context) and a third
        # row carrying the location ("Chapter 12 · Health Club · Line 46"). A slim
        # scrollbar in the left gutter appears whenever more results exist than fit.
        #
        # The component owns no query/selection state. It re-renders from the
        # reader view-state store each frame and keeps only render-derived scroll
        # geometry, so application-side input edits flow straight through.
        class InBookSearchPopupComponent < BaseComponent
          include BottomLeftPanel
          include OverlayMouseTarget
          include Ui::PanelSpans

          Palette = StatusBar::Palette

          ROWS_PER_RESULT = 3  # two snippet rows + one location row
          MAX_RESULTS = 5      # result ceiling when the panel keeps its natural width
          MAX_RESULTS_TALL = 7 # taller ceiling when it shrinks to the left margin
          SCROLLBAR_WIDTH = 1
          RIGHT_GAP = 1 # blank column kept to the right of the text (before the scrollbar or panel edge)
          MAX_WIDTH = 140
          MIN_WIDTH = 28
          SCROLL_GLYPH = '█'

          attr_reader :query, :results, :selected_index, :scroll_offset, :total_matches

          def initialize(reader_state_reader:, color_mode: :dark, rendered_lines: nil)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = color_mode
            @rendered_lines = rendered_lines
            @query = ''
            @results = []
            @selected_index = 0
            @scroll_offset = 0
            @total_matches = 0
            @visible_results = 1
          end

          def visible?
            @reader_state_reader&.mode == :in_book_search
          end

          def update_color_mode(mode)
            @color_mode = mode
          end

          def update_rendered_lines(rendered_lines)
            @rendered_lines = rendered_lines
          end

          def do_render(surface, bounds)
            clear_overlay_geometry
            return unless visible?

            sync_from_state
            return if @results.empty?

            layout = list_layout(bounds)
            return unless layout

            ensure_selection_visible!(layout[:visible])
            record_overlay_geometry(
              rule_row: layout[:rule_row], col: layout[:col], width: layout[:width],
              visible: layout[:visible], rows_per: ROWS_PER_RESULT,
              scroll: @scroll_offset, count: @results.length
            )
            render_list(surface, bounds, layout)
          end

          private

          # Refresh the render cache from the observable search state each frame.
          def sync_from_state
            reader = @reader_state_reader
            @query = (reader&.search_query || '').to_s
            @results = normalize_results(reader&.search_results || [])
            @total_matches = (reader&.search_total_matches || 0).to_i
            @selected_index = (reader&.search_selected_index || 0).to_i
            @hover_index = reader&.overlay_hover_index
            clamp_selection!
          end

          # The mouse-hovered row, when it is not already the selected row and is
          # a real result (a stale index from another overlay never lights up).
          def hovered_row?(absolute)
            !@hover_index.nil? && absolute == @hover_index && absolute != @selected_index &&
              absolute.between?(0, @results.length - 1)
          end

          # The list snaps flush to the left edge and docks its bottom row onto the
          # status bar, growing upward in whole three-row blocks. It shrinks to the
          # reader's empty left margin when one exists (so it never overlaps the
          # text) and shows more results in return; otherwise it keeps its width.
          def list_layout(bounds)
            bottom_row = bounds.height - 1
            available = bottom_row - 1 # rows for the top rule plus the result blocks
            return nil if bounds.width < MIN_WIDTH || available < ROWS_PER_RESULT

            width, constrained = fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH)
            @visible_results = visible_result_count(constrained, available)
            clamp_scroll!
            build_list_layout(width, bottom_row)
          end

          def visible_result_count(constrained, available)
            cap = row_ceiling(constrained, MAX_RESULTS, MAX_RESULTS_TALL)
            [[@results.length, cap, available / ROWS_PER_RESULT].min, 1].max
          end

          def build_list_layout(width, bottom_row)
            content_rows = @visible_results * ROWS_PER_RESULT
            {
              col: 1, width: width, bottom_row: bottom_row,
              visible: @visible_results, content_rows: content_rows,
              rule_row: bottom_row - content_rows, scrollbar: @results.length > @visible_results
            }
          end

          def render_list(surface, bounds, layout)
            render_top_rule(surface, bounds, layout)
            render_scrollbar(surface, bounds, layout) if layout[:scrollbar]
            layout[:visible].times { |slot| render_result_block(surface, bounds, layout, slot) }
          end

          # A hairline panel edge above the list, with a "more" hint for results
          # scrolled off the top.
          def render_top_rule(surface, bounds, layout)
            row = layout[:rule_row]
            return if row < 1

            label = @scroll_offset.positive? ? " ↑ #{@scroll_offset} more " : ''
            dashes = [layout[:width] - visible_length(label), 0].max
            rule = "#{Palette::RESET}#{Palette::LIST_BG}#{Palette::LIST_DIM_FG}#{label}" \
                   "#{Palette::LIST_RULE_FG}#{'─' * dashes}#{Palette::RESET}"
            surface.write(bounds, row, layout[:col], rule)
          end

          # A slim scrollbar down the panel's right side: a full-height █ track in a
          # lighter tone, with a brighter █ thumb (the "wheel") sized and positioned
          # to the visible slice of the result set.
          def render_scrollbar(surface, bounds, layout)
            rows = layout[:content_rows]
            thumb = Ui::ListHelpers.scrollbar_thumb(total: @results.length, visible: layout[:visible],
                                                    scroll: @scroll_offset, track_rows: rows)
            top = layout[:rule_row] + 1
            col = layout[:col] + layout[:width] - 1
            rows.times do |offset|
              in_thumb = offset >= thumb[:start] && offset < thumb[:start] + thumb[:size]
              color = in_thumb ? Palette::LIST_SCROLL_THUMB_FG : Palette::LIST_SCROLL_TRACK_FG
              surface.write(bounds, top + offset, col, "#{Palette::RESET}#{Palette::LIST_BG}#{color}#{SCROLL_GLYPH}")
            end
          end

          def render_result_block(surface, bounds, layout, slot)
            absolute = @scroll_offset + slot
            result = @results[absolute]
            return unless result

            reserve = layout[:scrollbar] ? SCROLLBAR_WIDTH : 0
            selected = absolute == @selected_index
            background = row_background(selected, hovered_row?(absolute))
            rows = block_rows(result, layout[:width] - reserve, selected, background)
            top = layout[:rule_row] + 1 + (slot * ROWS_PER_RESULT)
            rows.each_with_index { |row, offset| surface.write(bounds, top + offset, layout[:col], row) }
          end

          # RIGHT_GAP keeps the text clear of the panel's right edge (the
          # scrollbar, or just the margin) while the row's background still fills
          # the gap column, so the strip reads as one panel.
          def block_rows(result, width, selected, background)
            InBookSearch::ResultRow.new(result).render(width: width, selected: selected,
                                                       background: background, right_gap: RIGHT_GAP)
          end

          def row_background(selected, hovered)
            return Palette::LIST_SELECTED_BG if selected
            return Palette::LIST_HOVER_BG if hovered

            Palette::LIST_BG
          end

          def panel_bg = Palette::LIST_BG

          def normalize_results(results)
            Array(results).filter_map do |entry|
              next unless entry

              if entry.is_a?(Hash)
                normalize_result_hash(entry)
              elsif entry.is_a?(Struct) || entry.is_a?(Data)
                normalize_result_hash(entry.to_h)
              end
            end
          end

          def normalize_result_hash(entry)
            {
              chapter_index: result_value(entry, :chapter_index).to_i,
              chapter_title: result_value(entry, :chapter_title).to_s,
              line_index: result_value(entry, :line_index).to_i,
              before: result_value(entry, :before).to_s,
              match: result_value(entry, :match).to_s,
              after: result_value(entry, :after).to_s,
            }
          end

          def result_value(entry, key)
            return entry[key] if entry.key?(key)

            entry[key.to_s]
          end

          def ensure_selection_visible!(visible)
            @scroll_offset = Ui::ListHelpers.scroll_to_reveal(
              @selected_index, scroll: @scroll_offset, visible: visible, total: @results.length
            )
          end

          def clamp_selection!
            @selected_index = @results.empty? ? 0 : @selected_index.clamp(0, @results.length - 1)
          end

          def clamp_scroll!
            max = [@results.length - [@visible_results, 1].max, 0].max
            @scroll_offset = @scroll_offset.clamp(0, max)
          end
        end
      end
    end
  end
end
