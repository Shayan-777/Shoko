# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        class InBookSearchPopupComponent
          # Rendering and layout helpers for the in-book search popup.
          module RenderSupport
            private

            def render_header(context)
              row = context[:layout].origin_y + PADDING_V
              title = style_text('In-Book Search', color: panel_fg_emphasis, bold: true)
              badge = style_text(match_counter_text, color: glass_fg)
              context[:surface].write(
                context[:bounds], row, context[:x],
                pad_line(align_left_right(title, badge, context[:width]), context[:width], row: row, col: context[:x])
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
                          style_text('Type your query, then press Enter to search.', color: glass_fg)
                        elsif query_needs_search?
                          style_text("Press Enter to search for '#{@query}'.", color: panel_fg_emphasis)
                        elsif @total_matches.zero?
                          style_text("No matches for '#{@query}'.", color: panel_fg_emphasis)
                        else
                          style_text("Found #{@total_matches} match#{plural_suffix(@total_matches, 'es')}.",
                                     color: glass_fg)
                        end
              context[:surface].write(
                context[:bounds], row, context[:x], pad_line(message, context[:width], row: row, col: context[:x])
              )
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
              left = style_text(before, color: glass_fg)
              middle = style_text(match, color: panel_fg_emphasis, bold: true)
              right = style_text(after, color: glass_fg)
              " #{left}#{middle}#{right}"
            end

            def build_meta_line(result)
              chapter = result[:chapter_title].to_s.strip
              chapter = "Chapter #{result[:chapter_index].to_i + 1}" if chapter.empty?
              line_index = result[:line_index].to_i + 1
              style_text(" #{chapter} • line #{line_index}", color: glass_fg)
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

            def fill_panel_background(surface, bounds, layout)
              background = panel_bg
              layout.height.times do |offset|
                row = layout.origin_y + offset
                backdrop = backdrop_segment(row, layout.origin_x, layout.width)
                surface.write(bounds, row, layout.origin_x, "#{background}#{backdrop_fg}#{backdrop}#{reset}")
              end
            end

            def overlay_layout(bounds)
              width = @overlay_sizing.width_for(bounds.width)
              height = @overlay_sizing.height_for(bounds.height)
              Ui::OverlayLayout.centered(bounds, width: width, height: height)
            end

            def backdrop_segment(row, col, width)
              @backdrop_overlay.segment(row, col, width)
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

            def pad_line(text, width, row: nil, col: nil)
              safe = apply_background_reset(text.to_s)
              safe_width = visible_length(safe)
              pad = [width - safe_width, 0].max
              pad_text = if row.nil? || col.nil?
                           ' ' * pad
                         else
                           backdrop_segment(row, col + safe_width, pad)
                         end
              "#{panel_bg}#{safe}#{backdrop_fg}#{pad_text}#{reset}"
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
              @color_mode == :light ? PANEL_BG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT
            end

            def panel_fg
              @color_mode == :light ? PANEL_FG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_FG_DEFAULT
            end

            def panel_fg_emphasis
              @color_mode == :light ? PANEL_FG_EMPHASIS_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_FG_SELECTED
            end

            def glass_fg
              @color_mode == :light ? GLASS_FG_LIGHT : Adapters::Ui::Constants::Ui::TOOLTIP_GLASS_FG_DEFAULT
            end

            def backdrop_fg
              @color_mode == :light ? BACKDROP_FG_LIGHT : BACKDROP_FG_DARK
            end

            def reset
              Shoko::Shared::Terminal::Ansi::RESET
            end
          end
        end
      end
    end
  end
end
