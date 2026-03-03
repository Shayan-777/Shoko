# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative 'dictionary/entry_formatter'
require_relative 'dictionary_popup/setup_flow'
require_relative 'dictionary_popup/results_flow'
require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/key_definitions'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay component for dictionary lookup results.
        # Dark, clean design that blends with the reader background.
        class DictionaryPopupComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include DictionaryPopup::SetupFlow
          include DictionaryPopup::ResultsFlow

          # Background colors for dark/light modes
          POPUP_BG = "\e[48;5;236m"        # Dark gray (blends with dark reader)
          POPUP_BG_LIGHT = "\e[48;5;254m"  # Light gray (blends with light reader)
          CARD_BG = "\e[48;5;238m"
          CARD_BG_LIGHT = "\e[48;5;252m"

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
            @setup_mode = false
            @setup_state = {}
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.55,
              width_padding: 10,
              min_width: 42,
              height_ratio: 0.50,
              height_padding: 8,
              min_height: 10
            )
            @setup_overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.58,
              width_padding: 8,
              min_width: 54,
              height_ratio: 0.42,
              height_padding: 8,
              min_height: 12
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
            @setup_mode = false
            @setup_state = {}
          end

          def hide
            @visible = false
            @result = nil
            @formatted_lines = []
            @scroll_offset = 0
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @setup_mode = false
            @setup_state = {}
          end

          def visible?
            @visible
          end

          def scroll_up
            @scroll_offset = [@scroll_offset - 1, 0].max
          end

          def scroll_down(max_scroll = nil)
            limit = max_scroll.nil? ? max_scroll_offset : max_scroll
            @scroll_offset = [@scroll_offset + 1, limit].min
          end

          def insert_char(char)
            return nil unless @visible && @setup_mode

            handle_setup_key(char.to_s)
          end

          def backspace
            return nil unless @visible && @setup_mode

            handle_setup_key(Shared::KeyDefinitions::ACTIONS[:backspace].first)
          end

          def confirm
            return nil unless @visible
            return nil unless @setup_mode

            handle_setup_key(Shared::KeyDefinitions::ACTIONS[:confirm].first)
          end

          def cancel
            return nil unless @visible

            { type: :close }
          end

          def tab
            return nil unless @visible && @setup_mode

            handle_setup_key("\t")
          end

          def swap_languages
            return nil unless @visible && @setup_mode

            handle_setup_key('S')
          end

          def scroll_up_action
            return nil unless @visible

            if @setup_mode
              emit_setup_selection(-1)
            else
              scroll_up
              { type: :scroll }
            end
          end

          def scroll_down_action
            return nil unless @visible

            if @setup_mode
              emit_setup_selection(1)
            else
              scroll_down
              { type: :scroll }
            end
          end

          def render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            @layout = layout

            if @setup_mode
              render_setup_panel(surface, bounds, layout)
            else
              render_panel(surface, bounds, layout)
            end
          end

          def do_render(surface, bounds)
            render(surface, bounds)
          end

          def handle_key(key)
            return nil unless @visible

            return handle_setup_key(key) if @setup_mode

            if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
              scroll_up_action
            elsif Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
              scroll_down_action
            elsif Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
              cancel
            elsif Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
              cancel
            end
          end

          def handle_click(_col, _row)
            nil
          end

          private

          def overlay_layout(bounds)
            sizing = @setup_mode ? @setup_overlay_sizing : @overlay_sizing
            width = sizing.width_for(bounds.width)
            height = sizing.height_for(bounds.height)

            if @setup_mode
              content_width = [width - (PADDING_H * 2), 12].max
              setup_lines = build_setup_lines(content_width)
              needed_height = setup_lines.length + (PADDING_V * 2) + 1
              max_height = [bounds.height - 4, 12].max
              height = [[height, needed_height].max, max_height].min
            end

            Ui::OverlayLayout.centered(bounds, width: width, height: height)
          end

          def card_line(content, width:, active:)
            bg = active ? active_card_bg : card_bg
            safe = apply_background_reset(content, bg)
            vis_len = visible_length(safe)
            padding = [width - vis_len - 2, 0].max
            "#{bg} #{safe}#{' ' * padding} #{panel_bg}"
          end

          def style_text(text, color: nil, bold: false, dim: false, italic: false)
            prefix = +''
            prefix << color.to_s if color
            prefix << Shoko::Shared::Terminal::Ansi::BOLD if bold
            prefix << Shoko::Shared::Terminal::Ansi::DIM if dim
            prefix << Shoko::Shared::Terminal::Ansi::ITALIC if italic
            "#{prefix}#{text}#{text_reset}"
          end

          def text_reset
            "\e[39;22;23;24m"
          end

          def pad_line(text, width)
            bg = panel_bg
            safe = apply_background_reset(text, bg)
            vis_len = visible_length(safe)
            padding = [width - vis_len, 0].max
            "#{bg}#{safe}#{' ' * padding}#{reset}"
          end

          def apply_background_reset(text, bg)
            text.to_s.gsub(reset, "#{text_reset}#{bg}")
          end

          def visible_length(text)
            Shared::Terminal::TextMetrics.visible_length(text.to_s)
          rescue Shoko::Error
            text.to_s.gsub(/\e\[[0-9;]*m/, '').length
          end

          def panel_bg
            @color_mode == :light ? POPUP_BG_LIGHT : POPUP_BG
          end

          def card_bg
            @color_mode == :light ? CARD_BG_LIGHT : CARD_BG
          end

          def active_card_bg
            @color_mode == :light ? "\e[48;5;250m" : "\e[48;5;240m"
          end

          def reset
            Shoko::Shared::Terminal::Ansi::RESET
          end

          def max_scroll_offset
            content_height = @last_content_height || 10
            [@formatted_lines.length - content_height, 0].max
          end
        end
      end
    end
  end
end
