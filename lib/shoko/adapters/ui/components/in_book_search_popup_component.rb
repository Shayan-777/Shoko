# frozen_string_literal: true

require_relative '../../../shared/type_coercion'

require_relative 'base_component'
require_relative 'ui/backdrop_overlay'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay for in-book full text search.
        class InBookSearchPopupComponent < BaseComponent
          require_relative 'in_book_search_popup/render_support'
          require_relative 'in_book_search_popup/result_support'

          include Adapters::Ui::Constants::Ui
          include RenderSupport
          include ResultSupport

          PANEL_BG_LIGHT = "\e[48;2;233;236;241m"
          PANEL_FG_LIGHT = "\e[38;2;32;38;48m"
          PANEL_FG_EMPHASIS_LIGHT = "\e[38;2;22;56;84m"
          GLASS_FG_LIGHT = "\e[38;2;116;126;141m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          BACKDROP_FG_DARK = "\e[38;2;34;38;50m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze
          BACKDROP_FG_LIGHT = "\e[38;2;224;228;234m#{Shoko::Shared::Terminal::Ansi::DIM}".freeze

          PADDING_H = 2
          PADDING_V = 1

          CARD_HEIGHT = 4
          CARD_GAP = 1
          CARD_STRIDE = CARD_HEIGHT + CARD_GAP

          attr_reader :visible, :query, :results, :selected_index, :scroll_offset, :total_matches

          def initialize(color_mode: :dark, rendered_lines: nil)
            super()
            @color_mode = normalize_color_mode(color_mode)
            @backdrop_overlay = Ui::BackdropOverlay.new(rendered_lines: rendered_lines, resilient: true)
            @visible = false
            @query = ''
            @results = []
            @selected_index = 0
            @scroll_offset = 0
            @total_matches = 0
            @results_query = ''
            @query_dirty = false
            @last_visible_cards = 1
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.68,
              width_padding: 8,
              min_width: 62,
              height_ratio: 0.62,
              height_padding: 6,
              min_height: 16
            )
          end

          def show(query: '', results: [], total_matches: nil)
            @visible = true
            update(query: query, results: results, total_matches: total_matches, results_query: query)
          end

          def update(query:, results:, total_matches: nil, results_query: nil)
            @query = query.to_s
            @results = normalize_results(results)
            @total_matches = total_matches.nil? ? @results.length : total_matches.to_i
            @results_query = results_query.to_s unless results_query.nil?
            @query_dirty = query_needs_search?
            clamp_selection!
            clamp_scroll!
          end

          def hide
            @visible = false
            @query = ''
            @results = []
            @selected_index = 0
            @scroll_offset = 0
            @total_matches = 0
            @results_query = ''
            @query_dirty = false
          end

          def visible?
            @visible
          end

          def update_color_mode(mode)
            @color_mode = normalize_color_mode(mode)
          end

          def update_rendered_lines(rendered_lines)
            @backdrop_overlay.update_rendered_lines(rendered_lines)
          end

          def insert_char(char)
            return nil unless @visible

            value = char.to_s
            return nil unless printable_input_char?(value)

            @query = "#{@query}#{value}"
            @query_dirty = query_needs_search?
            { type: :query_change, query: @query }
          end

          def backspace
            return nil unless @visible

            @query = @query[0...-1].to_s
            @query_dirty = query_needs_search?
            { type: :query_change, query: @query }
          end

          def confirm
            return nil unless @visible

            return { type: :submit_query, query: @query } if query_needs_search?

            selected = selected_result
            return { type: :open_result, result: selected } if selected

            { type: :submit_query, query: @query }
          end

          def cancel
            return nil unless @visible

            { type: :close }
          end

          def scroll_up_action
            return nil unless @visible

            move_selection(-1)
            { type: :scroll }
          end

          def scroll_down_action
            return nil unless @visible

            move_selection(1)
            { type: :scroll }
          end

          def render(surface, bounds)
            do_render(surface, bounds)
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            fill_panel_background(surface, bounds, layout)
            context = base_render_context(surface, bounds, layout)
            current_row = render_header(context)
            current_row = render_search_input(context.merge(row: current_row))
            current_row = render_status_line(context.merge(row: current_row))
            footer_row = layout.origin_y + layout.height - 1
            results_height = [footer_row - current_row, 1].max
            render_results(context.merge(row: current_row, height: results_height))
            render_footer(context.merge(row: footer_row))
          end

          def base_render_context(surface, bounds, layout)
            {
              surface: surface,
              bounds: bounds,
              layout: layout,
              x: layout.origin_x + PADDING_H,
              width: [layout.width - (PADDING_H * 2), 20].max,
            }
          end

          def handle_key(key)
            return nil unless @visible

            if cancel_key?(key)
              cancel
            elsif up_key?(key)
              scroll_up_action
            elsif down_key?(key)
              scroll_down_action
            elsif confirm_key?(key)
              confirm
            elsif backspace_key?(key)
              backspace
            elsif printable_input_char?(key)
              insert_char(key)
            end
          end

          private

          def normalize_color_mode(mode)
            mode.to_s == 'light' ? :light : :dark
          end

          def up_key?(key)
            Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
          end

          def down_key?(key)
            Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
          end

          def confirm_key?(key)
            Shared::KeyDefinitions::ACTIONS[:confirm].include?(key)
          end

          def cancel_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
          end

          def backspace_key?(key)
            Shared::KeyDefinitions::ACTIONS[:backspace].include?(key)
          end

          def printable_input_char?(key)
            return false unless key.is_a?(String)
            return false unless key.length == 1

            cp = key.ord
            cp >= 32 && cp != 127
          end
        end
      end
    end
  end
end
