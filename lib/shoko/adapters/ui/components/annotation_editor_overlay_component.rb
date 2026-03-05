# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
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
        # Styled to match the dictionary popup design.
        class AnnotationEditorOverlayComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::CursorBlink

          # Background colors matching dictionary popup
          POPUP_BG = "\e[48;5;236m"
          POPUP_BG_LIGHT = "\e[48;5;254m"
          QUOTE_BG = "\e[48;5;238m"
          QUOTE_BG_LIGHT = "\e[48;5;252m"

          SAVE_KEYS = ["\x13"].freeze # Ctrl+S
          BACKSPACE_KEYS = ["\x08", "\x7F", "\b"].freeze

          # Style codes
          BOLD = "\e[1m"
          DIM = "\e[2m"
          ITALIC = "\e[3m"
          RESET_STYLE = "\e[22;23;24m"

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :selected_text, :note, :chapter_index, :annotation_id

          def initialize(selected_text:, range:, chapter_index:, annotation: nil, color_mode: :dark)
            super()
            @selected_text = (selected_text || '').dup
            @range = range
            @chapter_index = chapter_index
            @color_mode = color_mode
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
            title = "#{BOLD}Annotation#{RESET_STYLE}"
            line = pad_line(title, context[:width])
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
            label = "#{DIM}Note:#{RESET_STYLE}"
            context[:surface].write(context[:bounds], start_row, context[:x], pad_line(label, context[:width]))

            note_start = start_row + 1
            note_height = [end_row - note_start, 1].max
            render_note_input(context, note_start, note_height)
          end

          def render_note_input(context, start_row, height)
            text = @note.to_s
            @note_inner_width = context[:width]
            render_state = note_render_state(text, context[:width], height)
            render_state[:start_row] = start_row
            render_state[:cursor_style] = "#{panel_bg}#{accent}"
            render_note_input_lines(context, render_state)
          end

          def render_footer(context)
            row = context[:layout].origin_y + context[:layout].height - 1
            hints = "#{DIM}Ctrl+S#{RESET_STYLE} save  #{DIM}Esc#{RESET_STYLE} cancel"
            context[:surface].write(context[:bounds], row, context[:x], pad_line(hints, context[:width]))

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

          def pad_line(text, width)
            bg = panel_bg
            len = visible_length(text)
            padding = [width - len, 0].max
            "#{bg}#{text}#{' ' * padding}#{reset}"
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
              context[:surface].write(
                context[:bounds], layout.origin_y + offset, layout.origin_x, "#{bg}#{' ' * layout.width}#{reset}"
              )
            end
          end

          def render_quote_lines(context, start_row, quote_width, lines)
            bg = panel_bg
            qbg = quote_bg
            current_row = start_row
            lines.each do |line|
              padded = line.ljust(quote_width)
              content = "#{bg}#{DIM}│#{RESET_STYLE}#{qbg} #{DIM}#{ITALIC}#{padded}#{RESET_STYLE}#{bg}"
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
              context[:surface].write(context[:bounds], row, context[:x], pad_line(line_text, context[:width]))
            end
          end

          def cursor_line_text(line_text, idx, context, state)
            return line_text unless idx == state[:cursor_row]

            inline_cursor_text(
              line_text,
              state[:cursor_col],
              width: context[:width],
              style_prefix: state[:cursor_style],
              restore_prefix: "#{panel_bg}#{COLOR_TEXT_PRIMARY}"
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
            styled[0] = "#{DIM}Write your annotation...#{RESET_STYLE}" if empty_text
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

          attr_reader :color_mode

          def panel_bg
            color_mode == :light ? POPUP_BG_LIGHT : POPUP_BG
          end

          def quote_bg
            color_mode == :light ? QUOTE_BG_LIGHT : QUOTE_BG
          end

          def accent
            RenderStyle.color(:accent)
          rescue Shoko::Error
            "\e[96m"
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end
        end
      end
    end
  end
end
