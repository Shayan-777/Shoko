# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
require_relative 'ui/overlay_layout'
require_relative '../../terminal/text_metrics'
require_relative '../../terminal/terminal'
require_relative '../../../input/key_definitions'
require_relative '../../terminal/terminal_sanitizer'

module Shoko
  module Adapters::Output::Ui::Components
    # Overlay for creating/editing annotations.
    # Styled to match the dictionary popup design.
    class AnnotationEditorOverlayComponent < BaseComponent
      include Adapters::Output::Ui::Constants::UI

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

      def initialize(selected_text:, range:, chapter_index:, annotation: nil)
        super()
        @selected_text = (selected_text || '').dup
        @range = range
        @chapter_index = chapter_index
        @annotation_id = annotation.is_a?(Hash) ? (annotation[:id] || annotation['id']) : nil
        note_source = annotation.is_a?(Hash) ? (annotation[:note] || annotation['note']) : nil
        @note = (note_source || '').dup
        @cursor_pos = @note.length
        @visible = true
        @button_regions = {}
        @overlay_sizing = UI::OverlaySizing.new(
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
        elsif key == "\r" || key == "\n"
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
        bg = panel_bg
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
        bg = panel_bg

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

        # Wrap note text
        lines = text.empty? ? [''] : word_wrap(text, width)

        # Calculate cursor line
        cursor_text = text[0...@cursor_pos] || ''
        cursor_lines = cursor_text.empty? ? [''] : word_wrap(cursor_text, width)
        cursor_line_idx = [cursor_lines.length - 1, 0].max

        # Viewport
        view_start = calc_viewport(cursor_line_idx, height, lines.length)
        visible = lines[view_start, height] || []

        # Render lines
        height.times do |i|
          row = start_row + i
          line_text = visible[i] || ''
          surface.write(bounds, row, x, pad_line(line_text, width))
        end

        # Placeholder
        if text.empty?
          ph = "#{DIM}Write your annotation...#{RESET_STYLE}"
          surface.write(bounds, start_row, x, pad_line(ph, width))
        end

        # Cursor
        cursor_row = cursor_line_idx - view_start
        if cursor_row >= 0 && cursor_row < height
          cursor_col_text = cursor_lines.last || ''
          col_offset = visible_length(cursor_col_text)
          col_offset = [col_offset, width - 1].min
          surface.write(bounds, start_row + cursor_row, x + col_offset,
                        "#{bg}#{accent}_#{RESET_STYLE}#{reset}")
        end
      end

      def render_footer(surface, bounds, layout, x, width)
        bg = panel_bg
        row = layout.origin_y + layout.height - 1

        hints = "#{DIM}Ctrl+S#{RESET_STYLE} save  #{DIM}Esc#{RESET_STYLE} cancel"
        surface.write(bounds, row, x, pad_line(hints, width))

        @button_regions = {
          save: { row: row, col: x, width: 12 },
          cancel: { row: row, col: x + 14, width: 10 }
        }
      end

      public

      def handle_backspace
        return if @cursor_pos.zero?

        @note = @note[0...(@cursor_pos - 1)] + @note[@cursor_pos..]
        @cursor_pos -= 1
      end

      def handle_enter
        @note = @note[0...@cursor_pos] + "\n" + @note[@cursor_pos..]
        @cursor_pos += 1
      end

      def handle_character(char)
        return unless printable?(char)

        @note = @note[0...@cursor_pos] + char + @note[@cursor_pos..]
        @cursor_pos += char.length
      end

      def handle_save
        { type: :save, note: @note }
      end

      private

      def backspace_key?(key)
        BACKSPACE_KEYS.include?(key)
      end

      def save_key?(key)
        SAVE_KEYS.include?(key)
      end

      def cancel_key?(key)
        Adapters::Input::KeyDefinitions::ACTIONS[:cancel].include?(key)
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
        Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(
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

      def visible_length(text)
        Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
      rescue StandardError
        text.to_s.gsub(/\e\[[0-9;]*m/, '').length
      end

      def overlay_layout(bounds)
        w = @overlay_sizing.width_for(bounds.width)
        h = @overlay_sizing.height_for(bounds.height)
        UI::OverlayLayout.centered(bounds, width: w, height: h)
      end

      def color_mode
        Shoko::Adapters::Output::Terminal::Terminal.color_mode
      rescue StandardError
        :dark
      end

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
        Terminal::ANSI::RESET
      end
    end
  end
end
