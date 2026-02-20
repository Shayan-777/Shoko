# frozen_string_literal: true

require_relative '../../../../shared/terminal/device'
require_relative '../../../../shared/terminal/text_metrics'

module Shoko
  module Adapters::Ui::Components
    # Namespace for annotation editor overlay helpers.
    module AnnotationEditorOverlay
      # Renders the footer buttons for the annotation editor overlay.
      class FooterRenderer
        SegmentSpec = Struct.new(:row, :col, :key, :text, :width, keyword_init: true)

        def initialize(background:, text_fg:, key_fg:)
          @background = background
          @text_fg = text_fg
          @key_fg = key_fg
        end

        def render(surface, bounds, geometry)
          button_row = geometry.buttons_row
          fill_footer(surface, bounds, geometry, button_row)
          save_spec, cancel_spec = segment_specs(geometry, button_row)

          draw_segment(surface, bounds, save_spec)
          draw_segment(surface, bounds, cancel_spec)

          abs_row = geometry.button_row_abs(bounds)
          {
            save: region_for(bounds, abs_row, save_spec),
            cancel: region_for(bounds, abs_row, cancel_spec),
          }
        end

        private

        def fill_footer(surface, bounds, geometry, button_row)
          footer_bg = "#{@background}#{' ' * geometry.content_width}#{Terminal::ANSI::RESET}"
          surface.write(bounds, button_row, geometry.content_x, footer_bg)
        end

        def segment_specs(geometry, button_row)
          save_spec = build_segment_spec(geometry, button_row, key: 'Ctrl+S', text: 'Save', align: :left)
          cancel_spec = build_segment_spec(geometry, button_row, key: 'Esc', text: 'Cancel', align: :right)

          min_cancel_col = save_spec.col + save_spec.width + 2
          max_cancel_col = geometry.content_x + geometry.content_width - cancel_spec.width
          cancel_spec.col = [min_cancel_col, max_cancel_col].min if cancel_spec.col < min_cancel_col

          [save_spec, cancel_spec]
        end

        def build_segment_spec(geometry, row, key:, text:, align:)
          label = "#{key} #{text}"
          width = Shoko::Shared::Terminal::TextMetrics.visible_length(label)

          col = if align == :right
                  geometry.content_x + geometry.content_width - width
                else
                  geometry.content_x
                end
          col = [col, geometry.content_x].max

          SegmentSpec.new(row: row, col: col, key: key, text: text, width: width)
        end

        def draw_segment(surface, bounds, spec)
          reset = Terminal::ANSI::RESET
          label = "#{@background}#{@key_fg}#{spec.key}#{reset}" \
                  "#{@background}#{@text_fg} #{spec.text}#{reset}"
          surface.write(bounds, spec.row, spec.col, label)
        end

        def region_for(bounds, abs_row, spec)
          { row: abs_row, col: bounds.x + spec.col - 1, width: spec.width }
        end
      end
    end
  end
end
