# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'dictionary/entry_formatter'

module Shoko
  module Adapters::Output::Ui::Components
    # Popup overlay component for dictionary lookup results.
    # Used when terminal is too narrow for the side panel.
    class DictionaryPopupComponent < BaseComponent
      include Adapters::Output::Ui::Constants::UI

      HEADER_HEIGHT = 2
      FOOTER_HEIGHT = 2

      attr_reader :visible, :scroll_offset, :result, :entry_index

      def initialize
        super()
        @visible = false
        @scroll_offset = 0
        @result = nil
        @formatted_lines = []
        @formatter = nil
        @entry_index = 0
        @fuzzy_mode = false
        @fuzzy_matches = []
        @overlay_sizing = UI::OverlaySizing.new(
          width_ratio: 0.75,
          width_padding: 8,
          min_width: 50,
          height_ratio: 0.7,
          height_padding: 4,
          min_height: 15
        )
      end

      def show(result)
        @result = result
        @visible = true
        @scroll_offset = 0
        @formatted_lines = []
        @entry_index = 0
        @fuzzy_mode = false
        @fuzzy_matches = []
      end

      def hide
        @visible = false
        @result = nil
        @formatted_lines = []
        @scroll_offset = 0
        @entry_index = 0
        @fuzzy_mode = false
        @fuzzy_matches = []
      end

      def visible?
        @visible
      end

      def scroll_up
        @scroll_offset = [@scroll_offset - 1, 0].max
      end

      def scroll_down(max_scroll)
        @scroll_offset = [@scroll_offset + 1, max_scroll].min
      end

      def next_entry
        return false unless @result && @result.entry_count > 1
        return false if @fuzzy_mode

        @entry_index = (@entry_index + 1) % @result.entry_count
        @formatted_lines = []
        @scroll_offset = 0
        true
      end

      def toggle_fuzzy(matches = nil)
        if @fuzzy_mode
          @fuzzy_mode = false
          @fuzzy_matches = []
        else
          @fuzzy_mode = true
          @fuzzy_matches = Array(matches)
        end
        @formatted_lines = []
        @scroll_offset = 0
      end

      def fuzzy_mode?
        @fuzzy_mode
      end

      def render(surface, bounds)
        do_render(surface, bounds)
      end

      def do_render(surface, bounds)
        return unless @visible

        layout = overlay_layout(bounds)
        render_background(surface, bounds, layout)
        render_border(surface, bounds, layout)
        render_header(surface, bounds, layout)
        render_content(surface, bounds, layout)
        render_footer(surface, bounds, layout)
      end

      def handle_key(key)
        return nil unless @visible

        if Adapters::Input::KeyDefinitions::NAVIGATION[:up].include?(key)
          scroll_up
          { type: :scroll }
        elsif Adapters::Input::KeyDefinitions::NAVIGATION[:down].include?(key)
          content_height = @last_content_height || 10
          max_scroll = [@formatted_lines.length - content_height, 0].max
          scroll_down(max_scroll)
          { type: :scroll }
        elsif Adapters::Input::KeyDefinitions::ACTIONS[:cancel].include?(key)
          { type: :close }
        elsif Adapters::Input::KeyDefinitions::ACTIONS[:quit].include?(key)
          { type: :close }
        end
      end

      def handle_click(col, row)
        return nil unless @visible

        # Check if click is outside popup bounds - close if so
        # This would need access to the layout which we don't have here
        # For now, let key handling deal with closing
        nil
      end

      private

      def overlay_layout(bounds)
        width = @overlay_sizing.width_for(bounds.width)
        height = @overlay_sizing.height_for(bounds.height)
        UI::OverlayLayout.centered(bounds, width: width, height: height)
      end

      def render_background(surface, bounds, layout)
        layout.fill_background(surface, bounds, background: ANNOTATION_PANEL_BG)
      end

      def render_border(surface, bounds, layout)
        reset = Terminal::ANSI::RESET
        dim = COLOR_TEXT_DIM
        bg = ANNOTATION_PANEL_BG

        # Top border
        top_border = "#{bg}#{dim}┌#{'─' * (layout.width - 2)}┐#{reset}"
        surface.write_abs(bounds, layout.start_row, layout.start_col, top_border)

        # Side borders
        (1...layout.height - 1).each do |y|
          row = layout.start_row + y
          surface.write_abs(bounds, row, layout.start_col, "#{bg}#{dim}│#{reset}")
          surface.write_abs(bounds, row, layout.start_col + layout.width - 1, "#{bg}#{dim}│#{reset}")
        end

        # Bottom border
        bottom_border = "#{bg}#{dim}└#{'─' * (layout.width - 2)}┘#{reset}"
        surface.write_abs(bounds, layout.start_row + layout.height - 1, layout.start_col, bottom_border)
      end

      def render_header(surface, bounds, layout)
        reset = Terminal::ANSI::RESET
        bg = ANNOTATION_PANEL_BG

        # Title
        title = ' Look Up'
        title_row = layout.start_row + 1
        surface.write_abs(bounds, title_row, layout.start_col + 2, "#{bg}#{ANNOTATION_HEADER_FG}#{title}#{reset}")

        # Close button
        close_text = "#{bg}#{COLOR_TEXT_DIM}[×]#{reset}"
        close_col = layout.start_col + layout.width - 5
        surface.write_abs(bounds, title_row, close_col, close_text)

        # Separator
        separator_row = layout.start_row + 2
        separator = "#{bg}#{COLOR_TEXT_DIM}#{'─' * (layout.width - 4)}#{reset}"
        surface.write_abs(bounds, separator_row, layout.start_col + 2, separator)
      end

      def render_content(surface, bounds, layout)
        return unless @result

        content_width = layout.width - 6
        content_start_row = layout.start_row + HEADER_HEIGHT + 1
        content_height = layout.height - HEADER_HEIGHT - FOOTER_HEIGHT - 2
        @last_content_height = content_height

        # Regenerate formatted lines if needed
        if @formatted_lines.empty?
          @formatter = Dictionary::EntryFormatter.new(width: content_width)
          @formatted_lines = if @fuzzy_mode
                               @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                             else
                               @formatter.format_result(@result, entry_index: @entry_index)
                             end
        end

        reset = Terminal::ANSI::RESET
        bg = ANNOTATION_PANEL_BG

        visible_lines = @formatted_lines[@scroll_offset, content_height] || []

        visible_lines.each_with_index do |line, idx|
          row = content_start_row + idx
          truncated = UI::TextUtils.truncate_text(line.to_s, content_width)
          # Pad with background color
          padded = truncated.ljust(content_width)
          surface.write_abs(bounds, row, layout.start_col + 3, "#{bg}#{padded}#{reset}")
        end

        # Fill remaining lines with background
        remaining = content_height - visible_lines.length
        remaining.times do |i|
          row = content_start_row + visible_lines.length + i
          surface.write_abs(bounds, row, layout.start_col + 3, "#{bg}#{' ' * content_width}#{reset}")
        end

        # Scroll indicators
        render_scroll_indicators(surface, bounds, layout, content_height)
      end

      def render_scroll_indicators(surface, bounds, layout, content_height)
        return if @formatted_lines.length <= content_height

        reset = Terminal::ANSI::RESET
        bg = ANNOTATION_PANEL_BG
        dim = COLOR_TEXT_DIM
        indicator_col = layout.start_col + layout.width - 3

        # Up arrow if scrolled down
        if @scroll_offset.positive?
          surface.write_abs(bounds, layout.start_row + HEADER_HEIGHT + 1, indicator_col, "#{bg}#{dim}▲#{reset}")
        end

        # Down arrow if more content below
        if @scroll_offset < @formatted_lines.length - content_height
          footer_row = layout.start_row + layout.height - FOOTER_HEIGHT - 1
          surface.write_abs(bounds, footer_row, indicator_col, "#{bg}#{dim}▼#{reset}")
        end
      end

      def render_footer(surface, bounds, layout)
        reset = Terminal::ANSI::RESET
        bg = ANNOTATION_PANEL_BG

        # Separator
        separator_row = layout.start_row + layout.height - 3
        separator = "#{bg}#{COLOR_TEXT_DIM}#{'─' * (layout.width - 4)}#{reset}"
        surface.write_abs(bounds, separator_row, layout.start_col + 2, separator)

        # Navigation hint
        hint = '↑↓ Scroll • Tab Next • f Fuzzy • L Pair • Esc Close'
        hint_row = layout.start_row + layout.height - 2
        hint_col = layout.start_col + (layout.width - hint.length) / 2
        surface.write_abs(bounds, hint_row, hint_col, "#{bg}#{COLOR_TEXT_DIM}#{hint}#{reset}")
      end
    end
  end
end
