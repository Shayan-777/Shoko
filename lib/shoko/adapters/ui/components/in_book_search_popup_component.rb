# frozen_string_literal: true

require_relative '../../../shared/type_coercion'

require_relative 'base_component'
require_relative 'ui/backdrop_overlay'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'
require_relative '../constants/component_palettes'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay for in-book full text search. Renders from the reader
        # view-state store (query/results/selection/total); input is handled
        # application-side and written to that state, so this component owns no
        # query/selection state of its own — only render-derived scroll geometry.
        class InBookSearchPopupComponent < BaseComponent
          require_relative 'in_book_search_popup/render_support'
          require_relative 'in_book_search_popup/result_support'

          include Adapters::Ui::Constants::Ui
          include RenderSupport
          include ResultSupport

          PADDING_H = 2
          PADDING_V = 1

          CARD_HEIGHT = 4
          CARD_GAP = 1
          CARD_STRIDE = CARD_HEIGHT + CARD_GAP

          attr_reader :query, :results, :selected_index, :scroll_offset, :total_matches

          def initialize(reader_state_reader:, color_mode: :dark, rendered_lines: nil)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = normalize_color_mode(color_mode)
            @backdrop_overlay = Ui::BackdropOverlay.new(rendered_lines: rendered_lines, resilient: true)
            @query = ''
            @results = []
            @selected_index = 0
            @scroll_offset = 0
            @total_matches = 0
            @results_query = ''
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

          def visible?
            @reader_state_reader&.mode == :in_book_search
          end

          def update_color_mode(mode)
            @color_mode = normalize_color_mode(mode)
          end

          def update_rendered_lines(rendered_lines)
            @backdrop_overlay.update_rendered_lines(rendered_lines)
          end

          def render(surface, bounds)
            do_render(surface, bounds)
          end

          def do_render(surface, bounds)
            return unless visible?

            sync_from_state
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

          private

          # Refresh the render cache from the observable search state each frame.
          # Scroll geometry stays render-derived (depends on the visible card
          # count computed during rendering).
          def sync_from_state
            reader = @reader_state_reader
            @query = (reader&.search_query || '').to_s
            @results = normalize_results(reader&.search_results || [])
            @results_query = (reader&.search_results_query || '').to_s
            @total_matches = (reader&.search_total_matches || 0).to_i
            @selected_index = (reader&.search_selected_index || 0).to_i
            clamp_selection!
            ensure_selection_visible!
          end

          def normalize_color_mode(mode)
            mode.to_s == 'light' ? :light : :dark
          end
        end
      end
    end
  end
end
