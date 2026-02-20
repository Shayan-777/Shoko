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
  module Adapters::Ui::Components
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
        bg = panel_bg

        # Fill entire panel with background
        layout.height.times do |offset|
          surface.write(bounds, layout.origin_y + offset, layout.origin_x,
                        "#{bg}#{' ' * layout.width}#{reset}")
        end

        content_x = layout.origin_x + PADDING_H
        content_width = layout.width - (PADDING_H * 2)
        current_row = layout.origin_y + PADDING_V

        # Header
        current_row = render_header(surface, bounds, content_x, content_width, current_row)

        # Quote block
        current_row = render_quote(surface, bounds, content_x, content_width, current_row)

        # Note section
        note_end_row = layout.origin_y + layout.height - 2
        render_note_section(surface, bounds, content_x, content_width, current_row, note_end_row)

        # Footer
        render_footer(surface, bounds, layout, content_x, content_width)
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

      def render_header(surface, bounds, x, width, row)
        panel_bg
        title = "#{BOLD}Annotation#{RESET_STYLE}"
        line = pad_line(title, width)
        surface.write(bounds, row, x, line)
        row + 2
      end

      def render_quote(surface, bounds, x, width, start_row)
        bg = panel_bg
        qbg = quote_bg

        text = sanitize_text(@selected_text)
        return start_row if text.empty?

        # Wrap to fit (leave space for quote bar)
        quote_width = width - 3
        lines = word_wrap(text, quote_width).first(2)

        current_row = start_row
        lines.each do |line|
          padded = line.ljust(quote_width)
          # Dim bar │ then quote background with dim italic text
          content = "#{bg}#{DIM}│#{RESET_STYLE}#{qbg} #{DIM}#{ITALIC}#{padded}#{RESET_STYLE}#{bg}"
          surface.write(bounds, current_row, x, "#{content}#{reset}")
          current_row += 1
        end

        current_row + 1
      end

      def render_note_section(surface, bounds, x, width, start_row, end_row)
        panel_bg

        # Label
        label = "#{DIM}Note:#{RESET_STYLE}"
        surface.write(bounds, start_row, x, pad_line(label, width))

        # Note area
        note_start = start_row + 1
        note_height = [end_row - note_start, 1].max

        render_note_input(surface, bounds, x, width, note_start, note_height)
      end

      def render_note_input(surface, bounds, x, width, start_row, height)
        bg = panel_bg
        text = @note.to_s
        @note_inner_width = width

        renderer = Ui::AnnotationMarkup::Styler.new(text)
        lines = renderer.render_lines(width)
        cursor_line_idx, cursor_col = renderer.cursor_position(@cursor_pos, width)

        # Viewport
        view_start = calc_viewport(cursor_line_idx, height, lines.length)
        visible = lines[view_start, height] || []
        line_reset = Ui::AnnotationMarkup::STYLE_RESET
        styled_visible = visible.map { |line| line + line_reset }

        # Render lines
        height.times do |i|
          row = start_row + i
          line_text = styled_visible[i] || ''
          surface.write(bounds, row, x, pad_line(line_text, width))
        end

        # Placeholder
        if text.empty?
          ph = "#{DIM}Write your annotation...#{RESET_STYLE}"
          surface.write(bounds, start_row, x, pad_line(ph, width))
        end

        # Cursor
        cursor_row = cursor_line_idx - view_start
        return unless cursor_row >= 0 && cursor_row < height

        col_offset = [cursor_col, width - 1].min
        visible, glyph = cursor_state
        return unless visible

        surface.write(bounds, start_row + cursor_row, x + col_offset,
                      "#{bg}#{accent}#{glyph}#{RESET_STYLE}#{reset}")
      end

      def render_footer(surface, bounds, layout, x, width)
        panel_bg
        row = layout.origin_y + layout.height - 1

        hints = "#{DIM}Ctrl+S#{RESET_STYLE} save  #{DIM}Esc#{RESET_STYLE} cancel"
        surface.write(bounds, row, x, pad_line(hints, width))

        @button_regions = {
          save: { row: row, col: x, width: 12 },
          cancel: { row: row, col: x + 14, width: 10 },
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
      rescue StandardError
        false
      end

      def sanitize_text(text)
        Shoko::Shared::Terminal::TextSanitizer.sanitize(
          text.to_s, preserve_newlines: false, preserve_tabs: false
        ).gsub(/\s+/, ' ').strip
      rescue StandardError
        text.to_s.gsub(/\s+/, ' ').strip
      end

      def word_wrap(text, width)
        return [''] if text.nil? || text.empty? || width <= 0

        lines = []
        text.split("\n", -1).each do |para|
          if para.empty?
            lines << ''
            next
          end

          current = ''
          para.split(/\s+/).each do |word|
            if current.empty?
              current = word
            elsif current.length + 1 + word.length <= width
              current += " #{word}"
            else
              lines << current
              current = word
            end
          end
          lines << current
        end

        lines.empty? ? [''] : lines
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

      def visible_length(text)
        Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
      rescue StandardError
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
      rescue StandardError
        "\e[96m"
      end

      def reset
        Shoko::Shared::Terminal::Ansi::RESET
      end
    end
  end
end
