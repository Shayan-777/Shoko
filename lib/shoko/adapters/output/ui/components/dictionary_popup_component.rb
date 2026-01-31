# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
require_relative 'ui/overlay_layout'
require_relative 'dictionary/entry_formatter'
require_relative '../../terminal/terminal'

module Shoko
  module Adapters::Output::Ui::Components
    # Popup overlay component for dictionary lookup results.
    # Dark, clean design that blends with the reader background.
    class DictionaryPopupComponent < BaseComponent
      include Adapters::Output::Ui::Constants::UI

      # Background colors for dark/light modes
      POPUP_BG = "\e[48;5;236m"        # Dark gray (blends with dark reader)
      POPUP_BG_LIGHT = "\e[48;5;254m"  # Light gray (blends with light reader)

      PADDING_H = 2
      PADDING_V = 1

      attr_reader :visible, :scroll_offset, :result, :entry_index

      def initialize(color_mode: :dark)
        super()
        @color_mode = color_mode
        @visible = false
        @scroll_offset = 0
        @result = nil
        @formatted_lines = []
        @formatter = nil
        @entry_index = 0
        @fuzzy_mode = false
        @fuzzy_matches = []
        @overlay_sizing = UI::OverlaySizing.new(
          width_ratio: 0.55,
          width_padding: 10,
          min_width: 42,
          height_ratio: 0.50,
          height_padding: 8,
          min_height: 10
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
        return unless @visible

        layout = overlay_layout(bounds)
        @layout = layout

        render_panel(surface, bounds, layout)
      end

      def do_render(surface, bounds)
        render(surface, bounds)
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

      def handle_click(_col, _row)
        nil
      end

      private

      def overlay_layout(bounds)
        width = @overlay_sizing.width_for(bounds.width)
        height = @overlay_sizing.height_for(bounds.height)
        UI::OverlayLayout.centered(bounds, width: width, height: height)
      end

      def render_panel(surface, bounds, layout)
        bg = panel_bg

        # Fill entire panel with dark background
        layout.height.times do |offset|
          surface.write(bounds, layout.origin_y + offset, layout.origin_x,
                        "#{bg}#{' ' * layout.width}#{reset}")
        end

        # Content area dimensions
        content_x = layout.origin_x + PADDING_H
        content_width = layout.width - (PADDING_H * 2)
        content_y = layout.origin_y + PADDING_V
        content_height = layout.height - (PADDING_V * 2) - 1
        @last_content_height = content_height

        render_content(surface, bounds, content_x, content_y, content_width, content_height)
        render_footer(surface, bounds, layout, content_x, content_width)
      end

      def render_content(surface, bounds, content_x, content_y, content_width, content_height)
        return unless @result

        bg = panel_bg

        # Generate formatted lines if needed
        if @formatted_lines.empty?
          @formatter = Dictionary::EntryFormatter.new(width: content_width, background: bg, color_mode: @color_mode)
          @formatted_lines = if @fuzzy_mode
                               @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                             else
                               @formatter.format_result(@result, entry_index: @entry_index)
                             end
        end

        # Visible slice
        visible_lines = @formatted_lines[@scroll_offset, content_height] || []

        visible_lines.each_with_index do |line, idx|
          row = content_y + idx
          padded = pad_line(line.to_s, content_width)
          surface.write(bounds, row, content_x, padded)
        end

        # Fill remaining empty lines
        remaining = content_height - visible_lines.length
        empty_line = "#{bg}#{' ' * content_width}#{reset}"
        remaining.times do |i|
          row = content_y + visible_lines.length + i
          surface.write(bounds, row, content_x, empty_line)
        end

        # Scroll indicators
        return unless @formatted_lines.length > content_height

        render_scroll_indicators(surface, bounds, content_x, content_y, content_width,
                                 content_height)
      end

      def render_scroll_indicators(surface, bounds, content_x, content_y, content_width, content_height)
        bg = panel_bg
        indicator_x = content_x + content_width - 1

        surface.write(bounds, content_y, indicator_x, "#{bg}\e[2m▲\e[22m") if @scroll_offset.positive?

        return unless @scroll_offset < @formatted_lines.length - content_height

        surface.write(bounds, content_y + content_height - 1, indicator_x, "#{bg}\e[2m▼\e[22m")
      end

      def render_footer(surface, bounds, layout, content_x, content_width)
        panel_bg
        footer_row = layout.origin_y + layout.height - 1

        # Subtle footer with key hints (using style resets that preserve bg)
        dim = "\e[2m"
        nodim = "\e[22m"
        hints = "#{dim}Esc#{nodim} close  #{dim}Tab#{nodim} next  #{dim}f#{nodim} fuzzy"
        padded = pad_line(hints, content_width)
        surface.write(bounds, footer_row, content_x, padded)
      end

      def pad_line(text, width)
        bg = panel_bg
        vis_len = visible_length(text)
        padding = [width - vis_len, 0].max
        "#{bg}#{text}#{' ' * padding}#{reset}"
      end

      def visible_length(text)
        Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
      rescue StandardError
        text.to_s.gsub(/\e\[[0-9;]*m/, '').length
      end

      def panel_bg
        @color_mode == :light ? POPUP_BG_LIGHT : POPUP_BG
      end

      def reset
        Terminal::ANSI::RESET
      end
    end
  end
end
