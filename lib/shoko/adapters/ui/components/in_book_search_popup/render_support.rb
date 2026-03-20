# frozen_string_literal: true

require_relative '../base_component'
require_relative 'render_support/layout_styling_support'
require_relative 'render_support/result_text_support'

module Shoko
  module Adapters
    module Ui
      module Components
        class InBookSearchPopupComponent < BaseComponent
          # Rendering and layout helpers for the in-book search popup.
          module RenderSupport
            include LayoutStylingSupport
            include ResultTextSupport

            private

            def render_header(context)
              row = context[:layout].origin_y + PADDING_V
              context[:surface].write(
                context[:bounds],
                row,
                context[:x],
                pad_line(header_line(context[:width]), context[:width], row: row, col: context[:x])
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
              context[:surface].write(
                context[:bounds],
                row,
                context[:x],
                pad_line(status_message, context[:width], row: row, col: context[:x])
              )
              row + 1
            end

            def header_line(width)
              title = style_text('In-Book Search', color: panel_fg_emphasis, bold: true)
              badge = style_text(match_counter_text, color: glass_fg)
              align_left_right(title, badge, width)
            end

            def status_message
              if @query.to_s.strip.empty?
                return style_text('Type your query, then press Enter to search.', color: glass_fg)
              end

              if query_needs_search?
                return style_text("Press Enter to search for '#{@query}'.", color: panel_fg_emphasis)
              end

              return style_text("No matches for '#{@query}'.", color: panel_fg_emphasis) if @total_matches.zero?

              style_text("Found #{@total_matches} match#{plural_suffix(@total_matches, 'es')}.", color: glass_fg)
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
              border_color = selected ? panel_fg_emphasis : glass_fg
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
              remaining.times do |offset|
                row = top + consumed + offset
                context[:surface].write(
                  context[:bounds], row, context[:x], pad_line('', context[:width], row: row, col: context[:x])
                )
              end
            end

            def render_scrollbar(context, visible_cards)
              top = context[:row]
              render_scrollbar_track(context, top)
              thumb_height, thumb_start = scrollbar_thumb_geometry(context[:height], visible_cards)
              render_scrollbar_thumb(context, top, thumb_start, thumb_height)
            end

            def render_footer(context)
              hints = "#{style_text('Esc', color: glass_fg)} close  " \
                      "#{style_text('↑↓', color: glass_fg)} navigate  " \
                      "#{style_text('Enter', color: glass_fg)} search/open result"
              context[:surface].write(
                context[:bounds],
                context[:row],
                context[:x],
                pad_line(hints, context[:width], row: context[:row], col: context[:x])
              )
            end

            def write_search_input_border(context, row, inner_width, position)
              border = search_border_text(inner_width, position)
              context[:surface].write(
                context[:bounds], row, context[:x], pad_line(border, context[:width], row: row, col: context[:x])
              )
            end

            def write_search_input_middle(context, row, inner_width)
              middle = style_text('│', color: glass_fg) +
                       pad_visible(search_middle_text, inner_width) +
                       style_text('│', color: glass_fg)
              context[:surface].write(
                context[:bounds], row, context[:x], pad_line(middle, context[:width], row: row, col: context[:x])
              )
            end

            def search_border_text(inner_width, position)
              left, right = position == :top ? %w[╭ ╮] : %w[╰ ╯]
              style_text(left, color: glass_fg) +
                style_text('─' * inner_width, color: glass_fg) +
                style_text(right, color: glass_fg)
            end

            def search_middle_text
              value = if @query.empty?
                        style_text('type a word or phrase...', color: glass_fg)
                      else
                        style_text(@query, color: panel_fg, bold: true)
                      end
              label = style_text('Search>', color: panel_fg_emphasis, bold: true)
              cursor = style_text('_', color: panel_fg_emphasis)
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
              context[:surface].write(
                context[:bounds], row, context[:x], pad_line(border, context[:width], row: row, col: context[:x])
              )
            end

            def write_card_body(context, row, options)
              inner_width = options[:inner_width]
              border_color = options[:border_color]
              content = options[:content]
              line = style_text('│', color: border_color) +
                     pad_visible(content, inner_width) +
                     style_text('│', color: border_color)
              context[:surface].write(
                context[:bounds], row, context[:x], pad_line(line, context[:width], row: row, col: context[:x])
              )
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
              track = style_text('│', color: glass_fg)
              context[:height].times do |offset|
                row = top + offset
                context[:surface].write(
                  context[:bounds], row, context[:bar_col], pad_line(track, 1, row: row, col: context[:bar_col])
                )
              end
            end

            def render_scrollbar_thumb(context, top, thumb_start, thumb_height)
              thumb = style_text('█', color: panel_fg_emphasis)
              thumb_height.times do |offset|
                row = top + thumb_start + offset
                context[:surface].write(
                  context[:bounds], row, context[:bar_col], pad_line(thumb, 1, row: row, col: context[:bar_col])
                )
              end
            end
          end
        end
      end
    end
  end
end
