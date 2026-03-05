# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay for in-book full text search.
        class InBookSearchPopupComponent < BaseComponent
          include Adapters::Ui::Constants::Ui

          POPUP_BG = "\e[48;5;236m"
          POPUP_BG_LIGHT = "\e[48;5;254m"

          PADDING_H = 2
          PADDING_V = 1

          CARD_HEIGHT = 4
          CARD_GAP = 1
          CARD_STRIDE = CARD_HEIGHT + CARD_GAP

          attr_reader :visible, :query, :results, :selected_index, :scroll_offset, :total_matches

          def initialize(color_mode: :dark)
            super()
            @color_mode = color_mode
            @visible = false
            @query = ''
            @results = []
            @selected_index = 0
            @scroll_offset = 0
            @total_matches = 0
            @results_query = ''
            @query_dirty = false
            @last_visible_cards = 1
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.68,
              width_padding: 8,
              min_width: 62,
              height_ratio: 0.62,
              height_padding: 6,
              min_height: 16
            )
          end

          def show(query: '', results: [], total_matches: nil)
            @visible = true
            update(query: query, results: results, total_matches: total_matches, results_query: query)
          end

          def update(query:, results:, total_matches: nil, results_query: nil)
            @query = query.to_s
            @results = normalize_results(results)
            @total_matches = total_matches.nil? ? @results.length : total_matches.to_i
            @results_query = results_query.to_s unless results_query.nil?
            @query_dirty = query_needs_search?
            clamp_selection!
            clamp_scroll!
          end

          def hide
            @visible = false
            @query = ''
            @results = []
            @selected_index = 0
            @scroll_offset = 0
            @total_matches = 0
            @results_query = ''
            @query_dirty = false
          end

          def visible?
            @visible
          end

          def insert_char(char)
            return nil unless @visible

            value = char.to_s
            return nil unless printable_input_char?(value)

            @query = "#{@query}#{value}"
            @query_dirty = query_needs_search?
            { type: :query_change, query: @query }
          end

          def backspace
            return nil unless @visible

            @query = @query[0...-1].to_s
            @query_dirty = query_needs_search?
            { type: :query_change, query: @query }
          end

          def confirm
            return nil unless @visible

            return { type: :submit_query, query: @query } if query_needs_search?

            selected = selected_result
            return { type: :open_result, result: selected } if selected

            { type: :submit_query, query: @query }
          end

          def cancel
            return nil unless @visible

            { type: :close }
          end

          def scroll_up_action
            return nil unless @visible

            move_selection(-1)
            { type: :scroll }
          end

          def scroll_down_action
            return nil unless @visible

            move_selection(1)
            { type: :scroll }
          end

          def render(surface, bounds)
            do_render(surface, bounds)
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            fill_panel_background(surface, bounds, layout)
            context = base_render_context(surface, bounds, layout)
            current_row = render_header(context)
            current_row = render_search_input(context.merge(row: current_row))
            current_row = render_status_line(context.merge(row: current_row))
            footer_row = layout.origin_y + layout.height - 1
            results_height = [footer_row - current_row, 1].max
            render_results(context.merge(row: current_row, height: results_height))
            render_footer(context.merge(row: footer_row))
          end

          def base_render_context(surface, bounds, layout)
            {
              surface: surface,
              bounds: bounds,
              layout: layout,
              x: layout.origin_x + PADDING_H,
              width: [layout.width - (PADDING_H * 2), 20].max,
            }
          end

          def handle_key(key)
            return nil unless @visible

            if cancel_key?(key)
              return cancel
            elsif up_key?(key)
              return scroll_up_action
            elsif down_key?(key)
              return scroll_down_action
            elsif confirm_key?(key)
              return confirm
            elsif backspace_key?(key)
              return backspace
            elsif printable_input_char?(key)
              return insert_char(key)
            end

            nil
          end

          private

          def render_header(context)
            title = style_text('In-Book Search', color: COLOR_TEXT_ACCENT, bold: true)
            badge = style_text(match_counter_text, color: COLOR_TEXT_DIM)
            context[:surface].write(
              context[:bounds], context[:layout].origin_y + PADDING_V, context[:x],
              pad_line(align_left_right(title, badge, context[:width]), context[:width])
            )
            context[:layout].origin_y + PADDING_V + 2
          end

          def render_search_input(context)
            row = context[:row]
            inner_width = [context[:width] - 2, 4].max
            write_search_input_border(context, row, inner_width, :top)
            write_search_input_middle(context, row + 1, inner_width)
            write_search_input_border(context, row + 2, inner_width, :bottom)
            row + 4
          end

          def render_status_line(context)
            row = context[:row]
            message = if @query.to_s.strip.empty?
                        style_text('Type your query, then press Enter to search.', color: COLOR_TEXT_DIM)
                      elsif query_needs_search?
                        style_text("Press Enter to search for '#{@query}'.", color: COLOR_TEXT_WARNING)
                      elsif @total_matches.zero?
                        style_text("No matches for '#{@query}'.", color: COLOR_TEXT_WARNING)
                      else
                        style_text("Found #{@total_matches} match#{plural_suffix(@total_matches, 'es')}.",
                                   color: COLOR_TEXT_DIM)
                      end
            context[:surface].write(context[:bounds], row, context[:x], pad_line(message, context[:width]))
            row + 1
          end

          def render_results(context)
            top = context[:row]
            visible_cards = [context[:height] / CARD_STRIDE, 1].max
            @last_visible_cards = visible_cards
            clamp_scroll!
            render_context = results_render_context(context, visible_cards, top)
            render_visible_cards(render_context)
            fill_remaining_rows(render_context, render_context[:visible].length)
            return unless render_context[:show_scrollbar]

            render_scrollbar(render_context, visible_cards)
          end

          def render_result_card(context, result, selected)
            row = context[:row]
            border_color = selected ? COLOR_TEXT_ACCENT : COLOR_TEXT_DIM
            inner_width = [context[:width] - 2, 4].max
            border_options = { inner_width: inner_width, border_color: border_color }
            write_card_border(context, row, border_options.merge(position: :top))
            write_card_body(context, row + 1, border_options.merge(content: build_snippet_line(result)))
            write_card_body(context, row + 2, border_options.merge(content: build_meta_line(result)))
            write_card_border(context, row + 3, border_options.merge(position: :bottom))
          end

          def fill_remaining_rows(context, rendered_cards)
            top = context[:row]
            consumed = rendered_cards * CARD_STRIDE
            remaining = [context[:height] - consumed, 0].max
            blank = pad_line('', context[:width])
            remaining.times do |offset|
              row = top + consumed + offset
              context[:surface].write(context[:bounds], row, context[:x], blank)
            end
          end

          def render_scrollbar(context, visible_cards)
            top = context[:row]
            render_scrollbar_track(context, top)
            thumb_height, thumb_start = scrollbar_thumb_geometry(context[:height], visible_cards)
            render_scrollbar_thumb(context, top, thumb_start, thumb_height)
          end

          def render_footer(context)
            hints = "#{style_text('Esc', color: COLOR_TEXT_DIM)} close  " \
                    "#{style_text('↑↓', color: COLOR_TEXT_DIM)} navigate  " \
                    "#{style_text('Enter', color: COLOR_TEXT_DIM)} search/open result"
            context[:surface].write(context[:bounds], context[:row], context[:x], pad_line(hints, context[:width]))
          end

          def match_counter_text
            shown = @results.length
            total = @total_matches.to_i
            if total > shown
              "#{shown}/#{total} shown"
            else
              "#{shown} result#{plural_suffix(shown, 's')}"
            end
          end

          def plural_suffix(count, suffix)
            count == 1 ? '' : suffix
          end

          def build_snippet_line(result)
            before = result[:before].to_s
            match = result[:match].to_s
            after = result[:after].to_s
            left = style_text(before, color: COLOR_TEXT_SECONDARY)
            middle = style_text(match, color: COLOR_TEXT_ACCENT, bold: true)
            right = style_text(after, color: COLOR_TEXT_SECONDARY)
            " #{left}#{middle}#{right}"
          end

          def build_meta_line(result)
            chapter = result[:chapter_title].to_s.strip
            chapter = "Chapter #{result[:chapter_index].to_i + 1}" if chapter.empty?
            line_index = result[:line_index].to_i + 1
            style_text(" #{chapter} • line #{line_index}", color: COLOR_TEXT_DIM)
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
              chapter_index: normalize_result_number(entry, :chapter_index),
              chapter_title: normalize_result_text(entry, :chapter_title),
              line_index: normalize_result_number(entry, :line_index),
              before: normalize_result_text(entry, :before),
              match: normalize_result_text(entry, :match),
              after: normalize_result_text(entry, :after),
            }
          end

          def normalize_result_number(entry, key)
            result_value(entry, key).to_i
          end

          def normalize_result_text(entry, key)
            result_value(entry, key).to_s
          end

          def result_value(entry, key)
            return entry[key] if entry.key?(key)

            entry[key.to_s]
          end

          def write_search_input_border(context, row, inner_width, position)
            border = search_border_text(inner_width, position)
            context[:surface].write(context[:bounds], row, context[:x], pad_line(border, context[:width]))
          end

          def write_search_input_middle(context, row, inner_width)
            middle = style_text('│', color: COLOR_TEXT_DIM) +
                     pad_visible(search_middle_text, inner_width) +
                     style_text('│', color: COLOR_TEXT_DIM)
            context[:surface].write(context[:bounds], row, context[:x], pad_line(middle, context[:width]))
          end

          def search_border_text(inner_width, position)
            left, right = position == :top ? %w[╭ ╮] : %w[╰ ╯]
            style_text(left, color: COLOR_TEXT_DIM) +
              style_text('─' * inner_width, color: COLOR_TEXT_DIM) +
              style_text(right, color: COLOR_TEXT_DIM)
          end

          def search_middle_text
            value = if @query.empty?
                      style_text('type a word or phrase...', color: COLOR_TEXT_DIM)
                    else
                      style_text(@query, bold: true)
                    end
            label = style_text('Search>', color: COLOR_TEXT_ACCENT, bold: true)
            cursor = style_text('_', color: COLOR_TEXT_ACCENT)
            "#{label} #{value}#{cursor}"
          end

          def results_render_context(context, visible_cards, top)
            show_scrollbar = @results.length > visible_cards
            width = show_scrollbar ? [context[:width] - 2, 20].max : context[:width]
            {
              surface: context[:surface],
              bounds: context[:bounds],
              x: context[:x],
              row: top,
              height: context[:height],
              width: width,
              show_scrollbar: show_scrollbar,
              bar_col: context[:x] + width + 1,
              visible: @results[@scroll_offset, visible_cards] || [],
            }
          end

          def render_visible_cards(context)
            context[:visible].each_with_index do |result, idx|
              absolute_index = @scroll_offset + idx
              row = context[:row] + (idx * CARD_STRIDE)
              selected = absolute_index == @selected_index
              render_result_card(context.merge(row: row), result, selected)
            end
          end

          def write_card_border(context, row, options)
            inner_width = options[:inner_width]
            border_color = options[:border_color]
            position = options[:position]
            left, right = position == :top ? %w[╭ ╮] : %w[╰ ╯]
            border = style_text(left, color: border_color) +
                     style_text('─' * inner_width, color: border_color) +
                     style_text(right, color: border_color)
            context[:surface].write(context[:bounds], row, context[:x], pad_line(border, context[:width]))
          end

          def write_card_body(context, row, options)
            inner_width = options[:inner_width]
            border_color = options[:border_color]
            content = options[:content]
            line = style_text('│', color: border_color) +
                   pad_visible(content, inner_width) +
                   style_text('│', color: border_color)
            context[:surface].write(context[:bounds], row, context[:x], pad_line(line, context[:width]))
          end

          def scrollbar_thumb_geometry(height, visible_cards)
            total = @results.length
            max_scroll = [total - visible_cards, 0].max
            thumb_height = (height.to_f * visible_cards / total).round.clamp(1, height)
            return [thumb_height, 0] if max_scroll.zero? || height <= thumb_height

            thumb_start = ((@scroll_offset.to_f / max_scroll) * (height - thumb_height)).round
            [thumb_height, thumb_start]
          end

          def render_scrollbar_track(context, top)
            track = style_text('│', color: COLOR_TEXT_DIM)
            context[:height].times do |offset|
              context[:surface].write(context[:bounds], top + offset, context[:bar_col], pad_line(track, 1))
            end
          end

          def render_scrollbar_thumb(context, top, thumb_start, thumb_height)
            thumb = style_text('█', color: COLOR_TEXT_ACCENT)
            thumb_height.times do |offset|
              context[:surface].write(
                context[:bounds], top + thumb_start + offset, context[:bar_col], pad_line(thumb, 1)
              )
            end
          end

          def move_selection(delta)
            return if @results.empty?

            @selected_index = (@selected_index + delta.to_i).clamp(0, @results.length - 1)
            ensure_selection_visible!
          end

          def selected_result
            return nil if @results.empty?

            @results[@selected_index]
          end

          def query_needs_search?
            @query.to_s.strip != @results_query.to_s.strip
          end

          def ensure_selection_visible!
            visible = [@last_visible_cards, 1].max
            if @selected_index < @scroll_offset
              @scroll_offset = @selected_index
            elsif @selected_index >= (@scroll_offset + visible)
              @scroll_offset = @selected_index - visible + 1
            end
            clamp_scroll!
          end

          def clamp_selection!
            @selected_index = if @results.empty?
                                0
                              else
                                @selected_index.clamp(0, @results.length - 1)
                              end
          end

          def clamp_scroll!
            max = [@results.length - [@last_visible_cards, 1].max, 0].max
            @scroll_offset = @scroll_offset.clamp(0, max)
          end

          def fill_panel_background(surface, bounds, layout)
            background = panel_bg
            layout.height.times do |offset|
              surface.write(bounds, layout.origin_y + offset, layout.origin_x,
                            "#{background}#{' ' * layout.width}#{reset}")
            end
          end

          def overlay_layout(bounds)
            width = @overlay_sizing.width_for(bounds.width)
            height = @overlay_sizing.height_for(bounds.height)
            Ui::OverlayLayout.centered(bounds, width: width, height: height)
          end

          def align_left_right(left, right, width)
            left_len = visible_length(left)
            right_len = visible_length(right)
            gap = width - left_len - right_len
            return "#{left}#{' ' * gap}#{right}" if gap >= 1

            clipped_left = truncate_visible(left, [width - right_len - 1, 1].max)
            gap = [width - visible_length(clipped_left) - right_len, 1].max
            "#{clipped_left}#{' ' * gap}#{right}"
          end

          def pad_visible(text, width)
            clipped = truncate_visible(text.to_s, width)
            pad = [width - visible_length(clipped), 0].max
            "#{clipped}#{' ' * pad}"
          end

          def pad_line(text, width)
            safe = apply_background_reset(text.to_s)
            pad = [width - visible_length(safe), 0].max
            "#{panel_bg}#{safe}#{' ' * pad}#{reset}"
          end

          def apply_background_reset(text)
            text.gsub(reset, "#{text_reset}#{panel_bg}")
          end

          def truncate_visible(text, width)
            Shared::Terminal::TextMetrics.truncate_to(text, width)
          rescue Shoko::Error
            Ui::TextUtils.truncate_text(text.gsub(/\e\[[0-9;]*m/, ''), width)
          end

          def visible_length(text)
            Shared::Terminal::TextMetrics.visible_length(text.to_s)
          rescue Shoko::Error
            text.to_s.gsub(/\e\[[0-9;]*m/, '').length
          end

          def style_text(text, color: nil, bold: false, dim: false)
            prefix = +''
            prefix << color.to_s if color
            prefix << Shoko::Shared::Terminal::Ansi::BOLD if bold
            prefix << Shoko::Shared::Terminal::Ansi::DIM if dim
            "#{prefix}#{text}#{text_reset}"
          end

          def text_reset
            "\e[39;22;23;24m"
          end

          def panel_bg
            @color_mode == :light ? POPUP_BG_LIGHT : POPUP_BG
          end

          def up_key?(key)
            Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
          end

          def down_key?(key)
            Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
          end

          def confirm_key?(key)
            Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
          end

          def cancel_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
          end

          def backspace_key?(key)
            Shared::KeyDefinitions::ACTIONS[:backspace].include?(key)
          end

          def printable_input_char?(key)
            return false unless key.is_a?(String)
            return false unless key.length == 1

            cp = key.ord
            cp >= 32 && cp != 127
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end
        end
      end
    end
  end
end
