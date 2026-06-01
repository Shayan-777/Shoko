# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative 'rect'
require_relative 'dictionary/entry_formatter'
require_relative 'ui/text_utils'
require_relative '../../../shared/key_definitions'

module Shoko
  module Adapters
    module Ui
      module Components
        # Side panel component for displaying dictionary lookup results.
        # Renders to the right of the content area when terminal is wide enough.
        class DictionaryPanelComponent < BaseComponent
          include Adapters::Ui::Constants::Ui

          PANEL_WIDTH_PERCENT = 25
          MIN_WIDTH = 28
          HEADER_HEIGHT = 2
          FOOTER_HEIGHT = 2
          MIN_TERMINAL_WIDTH = 120

          attr_reader :visible, :scroll_offset, :result, :entry_index

          def initialize(state, color_mode: :dark)
            super()
            @state = state
            @color_mode = color_mode
            @visible = false
            @scroll_offset = 0
            @result = nil
            @formatted_lines = []
            @formatter = nil
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @last_width = nil
            @last_content_height = nil
          end

          def show(result)
            @result = result
            @visible = true
            @scroll_offset = 0
            @formatted_lines = []
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @last_width = nil
            @last_content_height = nil
          end

          def hide
            @visible = false
            @result = nil
            @formatted_lines = []
            @scroll_offset = 0
            @entry_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @last_width = nil
            @last_content_height = nil
          end

          def visible?
            @visible
          end

          def update_color_mode(mode)
            @color_mode = mode.to_s == 'light' ? :light : :dark
            @formatter = nil
            @formatted_lines = []
          end

          def scroll_up
            @scroll_offset = [@scroll_offset - 1, 0].max
          end

          def scroll_down(max_scroll = nil)
            limit = max_scroll.nil? ? max_scroll_offset : max_scroll
            @scroll_offset = [@scroll_offset + 1, limit].min
          end

          def scroll_up_action
            scroll_up
            { type: :scroll }
          end

          def scroll_down_action
            scroll_down
            { type: :scroll }
          end

          def cancel
            { type: :close }
          end

          def advance_entry!
            return nil unless @result && @result.entry_count > 1
            return nil if @fuzzy_mode

            @entry_index = (@entry_index + 1) % @result.entry_count
            @formatted_lines = []
            @scroll_offset = 0
            :advanced
          end
          alias next_entry advance_entry!

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

          # Calculate preferred width for this panel
          def preferred_width(total_width, content_right_edge = nil, available_width: nil)
            return :hidden unless @visible
            return :hidden if total_width < MIN_TERMINAL_WIDTH

            available = if available_width
                          available_width
                        elsif content_right_edge
                          total_width - content_right_edge
                        else
                          total_width / 3
                        end
            return :hidden if available < MIN_WIDTH

            preferred = (total_width * PANEL_WIDTH_PERCENT / 100.0).round
            width = [preferred, available].min
            [width, MIN_WIDTH].max
          end

          # Check if panel should display (sufficient terminal width)
          def should_display?(total_width)
            @visible && total_width >= MIN_TERMINAL_WIDTH
          end

          def do_render(surface, bounds)
            return unless @visible && bounds.width >= MIN_WIDTH

            sync_from_state
            if @last_width != bounds.width
              @formatter = nil
              @formatted_lines = []
              @last_width = bounds.width
            end

            draw_border(surface, bounds)
            render_header(surface, bounds)
            render_content(surface, bounds)
            render_footer(surface, bounds)
          end

          def handle_key(key)
            return nil unless @visible

            if Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
              scroll_up
              { type: :scroll }
            elsif Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
              content_height = calculate_content_height
              max_scroll = [@formatted_lines.length - content_height, 0].max
              scroll_down(max_scroll)
              { type: :scroll }
            elsif close_key?(key)
              { type: :close }
            end
          end

          def panel_bounds_for(total_width, total_height, content_right_edge)
            return nil unless should_display?(total_width)

            width = preferred_width(total_width, content_right_edge)
            return nil unless width.is_a?(Integer) && width.positive?

            x = total_width - width + 1
            Rect.new(x: x, y: 1, width: width, height: total_height)
          end


          # Rendering helpers for the side dictionary panel.
          PanelContentContext = Data.define(:surface, :bounds, :content_start_y, :content_height, :content_width)
          private

          # Lookup result/entry/fuzzy are observable reader view-state; pull them
          # in each render and invalidate the format cache when they change so a
          # new entry/pair/fuzzy toggle re-renders. (@state is the reader view
          # reader; absent in isolated component specs, which drive @result via #show.)
          def sync_from_state
            return unless @state.respond_to?(:dictionary_result)

            result = @state.dictionary_result
            entry_index = @state.dictionary_entry_index.to_i
            fuzzy_mode = @state.dictionary_fuzzy_mode == true
            fuzzy_matches = Array(@state.dictionary_fuzzy_matches)
            return if result == @result && entry_index == @entry_index &&
                      fuzzy_mode == @fuzzy_mode && fuzzy_matches == @fuzzy_matches

            @result = result
            @entry_index = entry_index
            @fuzzy_mode = fuzzy_mode
            @fuzzy_matches = fuzzy_matches
            @formatted_lines = nil
            @scroll_offset = 0
          end

          def calculate_content_height
            @last_content_height || 10
          end

          def max_scroll_offset
            [@formatted_lines.length - calculate_content_height, 0].max
          end

          def draw_border(surface, bounds)
            reset = Shoko::Shared::Terminal::Ansi::RESET
            dim = COLOR_TEXT_DIM

            # Draw left vertical border
            (1..bounds.height).each do |y|
              surface.write(bounds, y, 1, "#{dim}│#{reset}")
            end
          end

          def render_header(surface, bounds)
            reset = Shoko::Shared::Terminal::Ansi::RESET
            title = ' Look Up'
            surface.write(bounds, 1, 2, "#{SELECTION_HIGHLIGHT}#{title}#{reset}")

            # Close hint
            close_hint = "#{COLOR_TEXT_DIM}[Esc]#{reset}"
            close_x = bounds.width - 6
            surface.write(bounds, 1, close_x, close_hint) if close_x > 10

            # Separator line
            separator = "#{COLOR_TEXT_DIM}#{'─' * (bounds.width - 2)}#{reset}"
            surface.write(bounds, 2, 2, separator)
          end

          def render_scroll_indicators(surface, bounds, content_height)
            return if @formatted_lines.length <= content_height

            reset = Shoko::Shared::Terminal::Ansi::RESET
            dim = COLOR_TEXT_DIM

            # Up arrow if scrolled down
            surface.write(bounds, HEADER_HEIGHT + 1, bounds.width - 1, "#{dim}▲#{reset}") if @scroll_offset.positive?

            # Down arrow if more content below
            return unless @scroll_offset < @formatted_lines.length - content_height

            surface.write(bounds, bounds.height - FOOTER_HEIGHT, bounds.width - 1, "#{dim}▼#{reset}")
          end

          def render_footer(surface, bounds)
            reset = Shoko::Shared::Terminal::Ansi::RESET

            # Separator
            separator_y = bounds.height - FOOTER_HEIGHT
            separator = "#{COLOR_TEXT_DIM}#{'─' * (bounds.width - 2)}#{reset}"
            surface.write(bounds, separator_y, 2, separator)

            # Navigation hint
            hint = "#{COLOR_TEXT_DIM}↑↓ Scroll • Tab Next • f Fuzzy • L Pair • Esc Close#{reset}"
            clipped = Ui::TextUtils.truncate_text(hint, bounds.width - 4)
            surface.write(bounds, bounds.height - 1, 2, clipped)
          end

          def close_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key) ||
              Shared::KeyDefinitions::ACTIONS[:quit].include?(key)
          end

          def render_content(surface, bounds)
            return unless @result

            context = panel_content_context(surface, bounds)
            ensure_formatted_lines(context.content_width)
            @last_content_height = context.content_height
            clamp_scroll_offset(context.content_height)
            render_content_lines(context)
            render_scroll_indicators(surface, bounds, context.content_height)
          end

          def panel_content_context(surface, bounds)
            PanelContentContext.new(
              surface: surface,
              bounds: bounds,
              content_start_y: header_height + 1,
              content_height: bounds.height - header_height - footer_height,
              content_width: bounds.width - 4
            )
          end

          def ensure_formatted_lines(content_width)
            return unless @formatted_lines.empty?

            @formatter = Dictionary::EntryFormatter.new(width: content_width, color_mode: @color_mode)
            @formatted_lines = if @fuzzy_mode
                                 @formatter.format_fuzzy_results(@fuzzy_matches, @result.query)
                               else
                                 @formatter.format_result(@result, entry_index: @entry_index)
                               end
          end

          def clamp_scroll_offset(content_height)
            max_scroll = [@formatted_lines.length - content_height, 0].max
            @scroll_offset = [@scroll_offset, max_scroll].min
          end

          def render_content_lines(context)
            visible_lines = @formatted_lines[@scroll_offset, context.content_height] || []
            visible_lines.each_with_index do |line, index|
              row = context.content_start_y + index
              break if row > context.bounds.height - footer_height

              truncated = Ui::TextUtils.truncate_text(line.to_s, context.content_width)
              context.surface.write(context.bounds, row, 3, truncated)
            end
          end

          def header_height
            self.class::HEADER_HEIGHT
          end

          def footer_height
            self.class::FOOTER_HEIGHT
          end
        end
      end
    end
  end
end
