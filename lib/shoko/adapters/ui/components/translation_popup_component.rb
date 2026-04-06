# frozen_string_literal: true

require_relative 'base_component'
require_relative 'ui/overlay_layout'
require_relative 'ui/text_utils'
require_relative '../../../shared/terminal/ansi'
require_relative '../constants/component_palettes'
require_relative 'translation_popup/render_support'
require_relative 'translation_popup/content_support'
require_relative 'translation_popup/presentation_support'

module Shoko
  module Adapters
    module Ui
      module Components
        # Popup overlay for selected-text translation results.
        class TranslationPopupComponent < BaseComponent
          include Adapters::Ui::Constants::Ui
          include Ui::TextUtils
          include TranslationPopup::RenderSupport
          include TranslationPopup::ContentSupport
          include TranslationPopup::PresentationSupport

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :scroll_offset, :result

          def initialize(color_mode: :dark)
            super()
            @color_mode = normalize_color_mode(color_mode)
            @visible = false
            @scroll_offset = 0
            @result = nil
            @content_lines_cache = {}
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.58,
              width_padding: 10,
              min_width: 48,
              height_ratio: 0.44,
              height_padding: 8,
              min_height: 12
            )
            @last_content_width = 40
            @last_visible_body_lines = 1
          end

          def show(result)
            @result = result
            @scroll_offset = 0
            @visible = true
            clear_content_cache!
          end

          def hide
            @visible = false
            @scroll_offset = 0
            @result = nil
            clear_content_cache!
          end

          def visible?
            @visible
          end

          def update_color_mode(mode)
            @color_mode = normalize_color_mode(mode)
            clear_content_cache!
          end

          def scroll_up
            @scroll_offset = [@scroll_offset - 1, 0].max
          end

          def scroll_down
            @scroll_offset = [@scroll_offset + 1, max_scroll_offset].min
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            update_layout_state(layout)
            layout.fill_background(surface, bounds, background: panel_bg)
            context = render_context(surface: surface, bounds: bounds, layout: layout)
            render_frame(context)
            render_content(context)
          end

          private

          def update_layout_state(layout)
            @last_content_width = [layout.inner_width - (PADDING_H * 2), 20].max
            @last_visible_body_lines = [layout.inner_height - 6, 1].max
          end

          def render_context(surface:, bounds:, layout:)
            {
              surface: surface,
              bounds: bounds,
              layout: layout,
              x: layout.inner_x + PADDING_H - 1,
              row: layout.inner_y + PADDING_V - 1,
              width: @last_content_width,
            }
          end
        end
      end
    end
  end
end
