# frozen_string_literal: true

require_relative '../../../shared/type_coercion'
require_relative 'base_component'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'
require_relative 'status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        # In-book search results, rendered as an upward list that floats directly
        # above the bottom status bar (which hosts the "Search/<format>" input).
        # The list grows upward from the bar: the first/best match sits closest to
        # the input, with further matches stacked above it — an inverted, wider
        # cousin of an autocomplete dropdown.
        #
        # The component owns no query/selection state. It re-renders from the
        # reader view-state store each frame and keeps only render-derived scroll
        # geometry, so application-side input edits flow straight through.
        class InBookSearchPopupComponent < BaseComponent
          Palette = StatusBar::Palette

          MAX_ROWS = 9
          LEFT_MARGIN = 2
          RIGHT_MARGIN = 2
          MAX_WIDTH = 140
          MIN_WIDTH = 28
          MAX_LOCATION_WIDTH = 34
          POINTER = '▸ '

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
            @visible_rows = 1
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
            return unless visible?

            sync_from_state
            return if @results.empty?

            layout = list_layout(bounds)
            return unless layout

            ensure_selection_visible!(layout[:visible])
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
            clamp_selection!
          end

          # The list spans most of the width and anchors its bottom one row above
          # the status bar, growing upward.
          def list_layout(bounds)
            width = (bounds.width - LEFT_MARGIN - RIGHT_MARGIN).clamp(MIN_WIDTH, MAX_WIDTH)
            return nil if bounds.width < MIN_WIDTH + LEFT_MARGIN || bounds.height < 4

            bottom_row = bounds.height - 1          # row directly above the bar
            available = [bottom_row - 1, 1].max     # keep at least one content row visible
            visible = [@results.length, MAX_ROWS, available].min
            visible = 1 if visible < 1
            @visible_rows = visible
            clamp_scroll!

            {
              col: LEFT_MARGIN + 1,
              width: width,
              bottom_row: bottom_row,
              visible: visible,
              rule_row: bottom_row - visible,
            }
          end

          def render_list(surface, bounds, layout)
            render_top_rule(surface, bounds, layout)
            layout[:visible].times do |offset|
              absolute = @scroll_offset + offset
              result = @results[absolute]
              next unless result

              # Top-to-bottom: the first match sits just under the rule and the
              # list grows downward toward the bar (so ↓ moves the cursor down).
              line = result_line(result, layout[:width], absolute == @selected_index)
              surface.write(bounds, layout[:rule_row] + 1 + offset, layout[:col], line)
            end
          end

          # A hairline panel edge above the list, with a "more" hint for results
          # scrolled off the top.
          def render_top_rule(surface, bounds, layout)
            row = layout[:rule_row]
            return if row < 1

            label = @scroll_offset.positive? ? " ↑ #{@scroll_offset} more " : ''
            label_width = visible_length(label)
            dashes = [layout[:width] - label_width, 0].max
            rule = "#{Palette::RESET}#{Palette::LIST_BG}#{Palette::LIST_DIM_FG}#{label}" \
                   "#{Palette::LIST_RULE_FG}#{'─' * dashes}#{Palette::RESET}"
            surface.write(bounds, row, layout[:col], rule)
          end

          def result_line(result, width, selected)
            background = selected ? Palette::LIST_SELECTED_BG : Palette::LIST_BG
            pointer_width = visible_length(POINTER)
            location = location_text(result)
            location_width = visible_length(location)
            snippet_width = [width - pointer_width - location_width - 2, 6].max
            snippet, snippet_vis = snippet_segments(result, snippet_width, background)
            gap = [width - pointer_width - snippet_vis - location_width, 1].max

            "#{pointer_segment(selected, pointer_width, background)}#{snippet}" \
              "#{span(' ' * gap, Palette::LIST_DIM_FG, background)}" \
              "#{span(location, Palette::LIST_DIM_FG, background)}#{Palette::RESET}"
          end

          def pointer_segment(selected, width, background)
            return span(POINTER, Palette::LIST_POINTER_FG, background) if selected

            span(' ' * width, Palette::LIST_DIM_FG, background)
          end

          # Builds a "before [match] after" snippet that always keeps the matched
          # term visible, trimming context from the outer edges with ellipses.
          def snippet_segments(result, width, background)
            match = result[:match].to_s
            match_width = visible_length(match)
            return clipped_match_segment(match, width, background) if match_width >= width

            before, after = context_parts(result, width - match_width)
            text = "#{span(before, Palette::LIST_TEXT_FG, background)}#{match_segment(match, background)}" \
                   "#{span(after, Palette::LIST_TEXT_FG, background)}"
            [text, visible_length(before) + match_width + visible_length(after)]
          end

          def context_parts(result, remaining)
            left_budget = remaining / 2
            [clip_before(result[:before].to_s, left_budget), clip_after(result[:after].to_s, remaining - left_budget)]
          end

          def clipped_match_segment(match, width, background)
            clipped = truncate(match, width)
            [match_segment(clipped, background), visible_length(clipped)]
          end

          def match_segment(text, background)
            span(text, "#{Shoko::Shared::Terminal::Ansi::BOLD}#{Palette::LIST_MATCH_FG}", background)
          end

          # Keep the tail of the leading context (closest to the match).
          def clip_before(before, budget)
            return '' if budget <= 1
            return before if visible_length(before) <= budget

            trimmed = before
            trimmed = trimmed[1..].to_s while visible_length(trimmed) > budget - 1 && !trimmed.empty?
            "…#{trimmed}"
          end

          # Keep the head of the trailing context (closest to the match).
          def clip_after(after, budget)
            return after if visible_length(after) <= budget
            return '' if budget <= 1

            "#{truncate(after, budget - 1)}…"
          end

          def location_text(result)
            chapter = result[:chapter_title].to_s.strip
            chapter = "Chapter #{result[:chapter_index].to_i + 1}" if chapter.empty?
            line_index = result[:line_index].to_i + 1
            truncate("#{chapter} • line #{line_index}", MAX_LOCATION_WIDTH)
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
              line_space: result_value(entry, :line_space).to_s,
              page_index: optional_number(entry, :page_index),
            }
          end

          def optional_number(entry, key)
            value = result_value(entry, key)
            return nil if value.nil? || value.to_s.strip.empty?

            Shoko::Shared::TypeCoercion.optional_integer(value)
          end

          def result_value(entry, key)
            return entry[key] if entry.key?(key)

            entry[key.to_s]
          end

          def ensure_selection_visible!(visible)
            if @selected_index < @scroll_offset
              @scroll_offset = @selected_index
            elsif @selected_index >= @scroll_offset + visible
              @scroll_offset = @selected_index - visible + 1
            end
            clamp_scroll!
          end

          def clamp_selection!
            @selected_index = @results.empty? ? 0 : @selected_index.clamp(0, @results.length - 1)
          end

          def clamp_scroll!
            max = [@results.length - [@visible_rows, 1].max, 0].max
            @scroll_offset = @scroll_offset.clamp(0, max)
          end
        end
      end
    end
  end
end
