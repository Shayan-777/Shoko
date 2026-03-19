# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative 'dictionary/entry_formatter'
require_relative 'dictionary_popup/setup_flow'
require_relative 'dictionary_popup/results_flow'
require_relative 'dictionary_popup/presentation_support'
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
          include DictionaryPopup::PresentationSupport

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

          def update_color_mode(mode)
            @color_mode = mode.to_s == 'light' ? :light : :dark
            @formatter = nil
            @formatted_lines = []
            @scroll_offset = 0
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
            elsif close_key?(key)
              cancel
            end
          end

          def handle_click(_col, _row)
            nil
          end

          private

          def close_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key) ||
              Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
          end
        end
      end
    end
  end
end
