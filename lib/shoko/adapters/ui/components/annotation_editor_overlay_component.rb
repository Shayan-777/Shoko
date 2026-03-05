# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'ui/annotation_markup'
require_relative 'ui/annotation_list_input'
require_relative 'ui/cursor_blink'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Ui
      module Components
        # Overlay for creating/editing annotations.
        # Styled to match the tooltip popup glass design.
        class AnnotationEditorOverlayComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::CursorBlink

          SAVE_KEYS = ["\x13"].freeze # Ctrl+S
          BACKSPACE_KEYS = ["\x08", "\x7F", "\b"].freeze

          # Style codes
          BOLD = "\e[1m"
          DIM = "\e[2m"
          ITALIC = "\e[3m"
          RESET_STYLE = "\e[22;23;24m"
          PANEL_BG_LIGHT = "\e[48;2;233;236;241m"
          QUOTE_BG_LIGHT = "\e[48;2;220;226;234m"
          PANEL_FG_LIGHT = "\e[38;2;32;38;48m"
          PANEL_FG_EMPHASIS_LIGHT = "\e[38;2;22;56;84m"
          GLASS_FG_LIGHT = "\e[38;2;116;126;141m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          BACKDROP_FG_DARK = "\e[38;2;34;38;50m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          BACKDROP_FG_LIGHT = "\e[38;2;224;228;234m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :selected_text, :note, :chapter_index, :annotation_id

          def initialize(selected_text:, range:, chapter_index:, annotation: nil, color_mode: :dark,
                         rendered_lines: nil)
            super()
            @selected_text = (selected_text || '').dup
            @range = range
            @chapter_index = chapter_index
            @color_mode = color_mode
            @rendered_lines = rendered_lines.is_a?(Hash) ? rendered_lines : {}
            @backdrop_rows_key = nil
            @backdrop_rows = {}
            @annotation_id = annotation.is_a?(Hash) ? (annotation[:id] || annotation['id']) : nil
            note_source = annotation.is_a?(Hash) ? (annotation[:note] || annotation['note']) : nil
            @note = (note_source || '').dup
            @cursor_pos = @note.length
            @visible = true
            @button_regions = {}
            @note_inner_width = nil
            initialize_cursor_blink
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.55,
              width_padding: 10,
              min_width: 46,
              height_ratio: 0.50,
              height_padding: 8,
              min_height: 12
            )
          end

          def visible?
            @visible
          end

          def hide
            @visible = false
          end

          def update_color_mode(mode)
            @color_mode = mode.to_s == 'light' ? :light : :dark
          end

          def update_rendered_lines(rendered_lines)
            @rendered_lines = rendered_lines.is_a?(Hash) ? rendered_lines : {}
            @backdrop_rows_key = nil
            @backdrop_rows = {}
          end

          def selection_range
            @range
          end

          def render(surface, bounds)
            do_render(surface, bounds)
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            context = editor_render_context(surface, bounds, layout)
            fill_editor_background(context)
            current_row = render_header(context, context[:start_row])
            current_row = render_quote(context, current_row)
            note_end_row = layout.origin_y + layout.height - 2
            render_note_section(context, current_row, note_end_row)
            render_footer(context)
          end

          def handle_key(key)
            return { type: :cancel } if cancel_key?(key)
            return handle_save if save_key?(key)

            if backspace_key?(key)
              handle_backspace
            elsif ["\r", "\n"].include?(key)
              handle_enter
            elsif printable?(key)
              handle_character(key)
            end

            nil
          end

          def handle_click(col, row)
            return nil unless @visible && @button_regions

            @button_regions.each do |key, region|
              next unless row == region[:row]
              next unless col.between?(region[:col], region[:col] + region[:width] - 1)

              return handle_save if key == :save
              return { type: :cancel } if key == :cancel
            end

            nil
          end

          def calculate_width(total_width)
            @overlay_sizing.width_for(total_width)
          end

          def calculate_height(total_height)
            @overlay_sizing.height_for(total_height)
          end

          private

          def render_header(context, row)
            title = "#{panel_fg_emphasis}#{BOLD}Annotation#{RESET_STYLE}#{panel_fg}"
            line = pad_line(title, context[:width], row: row, col: context[:x])
            context[:surface].write(context[:bounds], row, context[:x], line)
            row + 2
          end

          def render_quote(context, start_row)
            text = sanitize_text(@selected_text)
            return start_row if text.empty?

            quote_width = context[:width] - 3
            lines = word_wrap(text, quote_width).first(2)
            render_quote_lines(context, start_row, quote_width, lines)
          end

          def render_note_section(context, start_row, end_row)
            label = "#{glass_fg}#{DIM}Note:#{RESET_STYLE}#{panel_fg}"
            context[:surface].write(
              context[:bounds],
              start_row,
              context[:x],
              pad_line(label, context[:width], row: start_row, col: context[:x])
            )

            note_start = start_row + 1
            note_height = [end_row - note_start, 1].max
            render_note_input(context, note_start, note_height)
          end

          def render_note_input(context, start_row, height)
            text = @note.to_s
            @note_inner_width = context[:width]
            render_state = note_render_state(text, context[:width], height)
            render_state[:start_row] = start_row
            render_state[:cursor_style] = "#{panel_bg}#{panel_fg_emphasis}"
            render_note_input_lines(context, render_state)
          end

          def render_footer(context)
            row = context[:layout].origin_y + context[:layout].height - 1
            hints = "#{glass_fg}#{DIM}Ctrl+S#{RESET_STYLE}#{panel_fg} save  " \
                    "#{glass_fg}#{DIM}Esc#{RESET_STYLE}#{panel_fg} cancel"
            context[:surface].write(
              context[:bounds],
              row,
              context[:x],
              pad_line(hints, context[:width], row: row, col: context[:x])
            )

            @button_regions = {
              save: { row: row, col: context[:x], width: 12 },
              cancel: { row: row, col: context[:x] + 14, width: 10 },
            }
          end

          public

          def handle_backspace
            return if @cursor_pos.zero?

            @note = @note[0...(@cursor_pos - 1)] + @note[@cursor_pos..]
            @cursor_pos -= 1
            record_cursor_activity
          end

          def handle_enter
            @note, @cursor_pos = Ui::AnnotationListInput.insert_newline(@note, @cursor_pos)
            record_cursor_activity
          end

          def handle_character(char)
            return unless printable?(char)

            @note, @cursor_pos = Ui::AnnotationListInput.insert_character(@note, @cursor_pos, char)
            record_cursor_activity
          end

          def handle_move_left
            move_cursor { |styler, cursor, width| styler.move_left(cursor, width) }
          end

          def handle_move_right
            move_cursor { |styler, cursor, width| styler.move_right(cursor, width) }
          end

          def handle_move_up
            move_cursor { |styler, cursor, width| styler.move_up(cursor, width) }
          end

          def handle_move_down
            move_cursor { |styler, cursor, width| styler.move_down(cursor, width) }
          end

          def handle_save
            { type: :save, note: @note }
          end

          def save_annotation
            handle_save
          end

          def cancel_annotation
            { type: :cancel }
          end

          private

          def backspace_key?(key)
            BACKSPACE_KEYS.include?(key)
          end

          def save_key?(key)
            SAVE_KEYS.include?(key)
          end

          def cancel_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
          end

          def printable?(key)
            return false unless key.is_a?(String)
            return false if key.length != 1

            cp = key.ord
            return false if cp < 0x20
            return false if cp == 0x7F
            return false if cp.between?(0x80, 0x9F)

            true
          end

          def sanitize_text(text)
            Shoko::Shared::Terminal::TextSanitizer.sanitize(
              text.to_s, preserve_newlines: false, preserve_tabs: false
            ).gsub(/\s+/, ' ').strip
          rescue Shoko::Error
            text.to_s.gsub(/\s+/, ' ').strip
          end

          def word_wrap(text, width)
            return [''] if text.nil? || text.empty? || width <= 0

            lines = []
            text.split("\n", -1).each do |para|
              append_wrapped_paragraph(lines, para, width)
            end

            lines.empty? ? [''] : lines
          end

          def append_wrapped_paragraph(lines, paragraph, width)
            if paragraph.empty?
              lines << ''
              return
            end

            current = ''
            paragraph.split(/\s+/).each do |word|
              current = append_wrapped_word(lines, current, word, width)
            end
            lines << current
          end

          def append_wrapped_word(lines, current, word, width)
            return word if current.empty?
            return "#{current} #{word}" if current.length + 1 + word.length <= width

            lines << current
            word
          end

          def calc_viewport(cursor_line, height, total)
            max_start = [total - height, 0].max
            start = [cursor_line - height + 1, 0].max
            [start, max_start].min
          end

          def pad_line(text, width, row:, col:)
            bg = panel_bg
            len = visible_length(text)
            padding = [width - len, 0].max
            padding_text = backdrop_segment(row, col + len, padding)
            "#{bg}#{panel_fg}#{text}#{backdrop_fg}#{padding_text}#{reset}"
          end

          def move_cursor
            width = @note_inner_width || 40
            styler = Ui::AnnotationMarkup::Styler.new(@note)
            @cursor_pos = yield(styler, @cursor_pos, width)
            record_cursor_activity
          end

          def editor_render_context(surface, bounds, layout)
            {
              surface: surface,
              bounds: bounds,
              layout: layout,
              x: layout.origin_x + PADDING_H,
              width: layout.width - (PADDING_H * 2),
              start_row: layout.origin_y + PADDING_V,
            }
          end

          def fill_editor_background(context)
            bg = panel_bg
            layout = context[:layout]
            layout.height.times do |offset|
              row = layout.origin_y + offset
              backdrop = backdrop_segment(row, layout.origin_x, layout.width)
              context[:surface].write(
                context[:bounds],
                row,
                layout.origin_x,
                "#{bg}#{backdrop_fg}#{backdrop}#{reset}"
              )
            end
          end

          def render_quote_lines(context, start_row, quote_width, lines)
            bg = panel_bg
            qbg = quote_bg
            current_row = start_row
            lines.each do |line|
              padded = line.ljust(quote_width)
              content = "#{bg}#{glass_fg}#{DIM}│#{RESET_STYLE}" \
                        "#{qbg}#{panel_fg_emphasis} #{DIM}#{ITALIC}#{padded}#{RESET_STYLE}" \
                        "#{bg}#{panel_fg}"
              context[:surface].write(context[:bounds], current_row, context[:x], "#{content}#{reset}")
              current_row += 1
            end
            current_row + 1
          end

          def note_viewport(lines, cursor_line_idx, height)
            view_start = calc_viewport(cursor_line_idx, height, lines.length)
            visible = lines[view_start, height] || []
            [visible, cursor_line_idx - view_start]
          end

          def render_note_input_lines(context, state)
            state[:height].times do |idx|
              row = state[:start_row] + idx
              line_text = state[:styled_visible][idx] || ''
              line_text = cursor_line_text(line_text, idx, context, state)
              context[:surface].write(
                context[:bounds],
                row,
                context[:x],
                pad_line(line_text, context[:width], row: row, col: context[:x])
              )
            end
          end

          def cursor_line_text(line_text, idx, context, state)
            return line_text unless idx == state[:cursor_row]

            inline_cursor_text(
              line_text,
              state[:cursor_col],
              width: context[:width],
              style_prefix: state[:cursor_style],
              restore_prefix: "#{panel_bg}#{panel_fg}"
            )
          end

          def note_render_state(text, width, height)
            renderer = Ui::AnnotationMarkup::Styler.new(text)
            lines = renderer.render_lines(width)
            cursor_line_idx, cursor_col = renderer.cursor_position(@cursor_pos, width)
            visible, cursor_row = note_viewport(lines, cursor_line_idx, height)
            {
              height: height,
              cursor_col: cursor_col,
              cursor_row: cursor_row,
              styled_visible: styled_note_lines(visible, text.empty?),
            }
          end

          def styled_note_lines(lines, empty_text)
            styled = lines.map { |line| line + Ui::AnnotationMarkup::STYLE_RESET }
            styled[0] = "#{glass_fg}#{DIM}Write your annotation...#{RESET_STYLE}#{panel_fg}" if empty_text
            styled
          end

          def visible_length(text)
            Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
          rescue Shoko::Error
            text.to_s.gsub(/\e\[[0-9;]*m/, '').length
          end

          def overlay_layout(bounds)
            w = @overlay_sizing.width_for(bounds.width)
            h = @overlay_sizing.height_for(bounds.height)
            Ui::OverlayLayout.centered(bounds, width: w, height: h)
          end

          def backdrop_segment(row, col, width)
            return '' if width <= 0

            cell_map = backdrop_cells_for_row(row)
            col_start = col.to_i
            col_end = col_start + width
            (col_start...col_end).map do |column|
              value = cell_map[column]
              next ' ' if value.nil? || value == :continuation

              backdrop_char(value)
            end.join
          end

          def backdrop_char(value)
            char = value.to_s
            return ' ' if char.empty? || char == ' '

            char
          end

          def backdrop_cells_for_row(row)
            cache = backdrop_row_cache
            return cache[row] if cache.key?(row)

            cache[row] = build_backdrop_cells(row)
          end

          def build_backdrop_cells(row)
            geometries_for_row(row).each_with_object({}) do |geometry, cells|
              merge_geometry_cells(cells, geometry)
            end
          end

          def geometries_for_row(row)
            lines = @rendered_lines
            return [] unless lines.is_a?(Hash)

            geometries = lines.each_value.filter_map do |entry|
              geometry = entry && entry[:geometry]
              next unless geometry
              next unless geometry.row.to_i == row.to_i

              geometry
            end

            geometries.sort_by { |geometry| geometry.column_origin.to_i }
          end

          def merge_geometry_cells(cells, geometry)
            Array(geometry.cells).each do |cell|
              merge_cell(cells, geometry, cell)
            end
          end

          def merge_cell(cells, geometry, cell)
            width = cell.display_width.to_i
            return if width <= 0

            absolute_column = geometry.column_origin.to_i + cell.screen_x.to_i
            cluster = cell.cluster.to_s
            cells[absolute_column] = cluster.empty? ? ' ' : cluster
            mark_continuation_cells(cells, absolute_column, width)
          end

          def mark_continuation_cells(cells, absolute_column, width)
            1.upto(width - 1) do |delta|
              cells[absolute_column + delta] = :continuation
            end
          end

          def backdrop_row_cache
            lines = @rendered_lines
            key = lines.object_id
            return @backdrop_rows if @backdrop_rows_key == key

            @backdrop_rows_key = key
            @backdrop_rows = {}
          end

          attr_reader :color_mode

          def panel_bg
            color_mode == :light ? PANEL_BG_LIGHT : TOOLTIP_BG_DEFAULT
          end

          def quote_bg
            color_mode == :light ? QUOTE_BG_LIGHT : TOOLTIP_BG_SELECTED
          end

          def panel_fg
            color_mode == :light ? PANEL_FG_LIGHT : TOOLTIP_FG_DEFAULT
          end

          def panel_fg_emphasis
            color_mode == :light ? PANEL_FG_EMPHASIS_LIGHT : TOOLTIP_FG_SELECTED
          end

          def glass_fg
            color_mode == :light ? GLASS_FG_LIGHT : TOOLTIP_GLASS_FG_DEFAULT
          end

          def backdrop_fg
            color_mode == :light ? BACKDROP_FG_LIGHT : BACKDROP_FG_DARK
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end
        end
      end
    end
  end
end
