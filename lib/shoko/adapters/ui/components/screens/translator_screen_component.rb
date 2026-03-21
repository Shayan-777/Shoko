# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../ui/box_drawer'
require_relative '../ui/text_utils'
require_relative 'translator_screen_component/palette_support'
require_relative 'translator_screen_component/state_support'
require_relative 'translator_screen_component/layout_support'
require_relative 'translator_screen_component/dropdown_support'
require_relative 'translator_screen_component/body_support'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Menu-mode translator screen with color-distinct source/target panes.
          class TranslatorScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::BoxDrawer
            include Ui::TextUtils
            include TranslatorScreenComponentPaletteSupport
            include TranslatorScreenComponentStateSupport
            include TranslatorScreenComponentLayoutSupport
            include TranslatorScreenComponentDropdownSupport
            include TranslatorScreenComponentBodySupport

            MAX_DROPDOWN_ROWS = 5
            DROPDOWN_CODE_WIDTH = 4

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              render_frame(surface, bounds)
              render_status(surface, bounds, layout)
              render_panel(surface, bounds, layout[:left_box], kind: :source)
              render_panel(surface, bounds, layout[:right_box], kind: :target)
            end

            def hit_test(column, row, bounds)
              layout = layout_metrics(bounds)
              source_hit = dropdown_hit(layout[:left_box], column, row, :source)
              return source_hit if source_hit

              target_hit = dropdown_hit(layout[:right_box], column, row, :target)
              return target_hit if target_hit
              return { type: :toggle_dropdown, kind: :source } if within_header?(layout[:left_box], column, row)
              return { type: :toggle_dropdown, kind: :target } if within_header?(layout[:right_box], column, row)
              return { type: :focus, focus: :input } if within_body?(layout[:left_box], column, row, :source)

              nil
            end

            private

            def render_frame(surface, bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Translator', hint: 'TAB focus  ENTER act  S swap  ESC back')
              frame.render_divider
              frame.render_footer(text: footer_text)
            end

            def render_status(surface, bounds, layout)
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:indent],
                left: status_message,
                right: detected_language_label,
                width: layout[:content_width],
                left_color: status_left_color,
                right_color: detected_language_label.empty? ? nil : panel_accent(:source)
              )
            end

            def render_panel(surface, bounds, box, kind:)
              draw_box(surface, bounds, box, border_color: panel_border_color(kind))
              render_panel_title(surface, bounds, box, kind)
              render_dropdown_trigger(surface, bounds, box, kind)
              render_panel_divider(surface, bounds, box, kind) unless dropdown_open_for?(kind)
              render_body(surface, bounds, box, kind)
              render_dropdown(surface, bounds, box, kind) if dropdown_open_for?(kind)
            end

            def render_panel_title(surface, bounds, box, kind)
              surface.write(
                bounds,
                box.row + 1,
                box.col + 2,
                panel_title_badge(kind)
              )
            end

            def render_panel_divider(surface, bounds, box, kind)
              line = '─' * [box.width - 4, 0].max
              surface.write(bounds, box.row + 3, box.col + 2, "#{panel_accent(kind)}#{DIM}#{line}#{reset}")
            end

            def render_body(surface, bounds, box, kind)
              body_lines(box, kind).each_with_index do |line, index|
                surface.write(bounds, body_start_row(box, kind) + index, box.col + 2, line)
              end
            end

            def dropdown_hit(box, column, row, kind)
              return nil unless dropdown_open_for?(kind)
              return nil unless within_dropdown?(box, column, row, kind)

              popup_box = dropdown_popup_box(box, kind)
              index = dropdown_window(kind)[:start] + row - dropdown_item_start_row(popup_box)
              item = language_options(kind)[index]
              return nil unless item

              { type: :select_language, kind: kind, code: item[:code], index: index }
            end

            def panel_active?(kind)
              return true if kind == :source && show_input_cursor?

              translator_focus == kind || dropdown_open_for?(kind)
            end

            def dropdown_open_for?(kind)
              current_mode == (kind == :source ? :translator_source_dropdown : :translator_target_dropdown)
            end

            def pad_body_line(text, width)
              Shoko::Shared::Terminal::TextMetrics.pad_right(text.to_s, width)
            end

            def empty_body_line(width)
              ' ' * width
            end

            def panel_title(kind)
              kind == :source ? 'SOURCE' : 'RESULT'
            end

            def panel_title_badge(kind)
              "#{dropdown_bg}#{panel_accent(kind)}#{BOLD} #{panel_title(kind)} #{reset}"
            end
          end
        end
      end
    end
  end
end
