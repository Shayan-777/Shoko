# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative 'master_detail_layout_builder'
require_relative 'status_renderer'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Shared shell for menu-mode screens that present a primary list and
          # an optional inspector/detail panel.
          class MasterDetailShell
            BRAND_LABEL = 'SHOKO'
            DEFAULT_DETAIL_WIDTH = MasterDetailLayoutBuilder::DEFAULT_DETAIL_WIDTH
            MIN_DETAIL_WIDTH = MasterDetailLayoutBuilder::MIN_DETAIL_WIDTH
            MIN_PRIMARY_WIDTH = MasterDetailLayoutBuilder::MIN_PRIMARY_WIDTH
            DEFAULT_STACKED_DETAIL_HEIGHT = MasterDetailLayoutBuilder::DEFAULT_STACKED_DETAIL_HEIGHT
            DEFAULT_PREFERRED_WIDTH = MasterDetailLayoutBuilder::SHELL_PREFERRED_WIDTH

            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
              @status_renderer = StatusRenderer.new(surface, bounds, tokens: tokens)
            end

            def build_layout(prelude_rows: 0, detail_visible: true, desired_detail_width: DEFAULT_DETAIL_WIDTH,
                             min_primary_width: MIN_PRIMARY_WIDTH, min_detail_width: MIN_DETAIL_WIDTH,
                             stacked_detail_height: DEFAULT_STACKED_DETAIL_HEIGHT,
                             preferred_width: DEFAULT_PREFERRED_WIDTH)
              MasterDetailLayoutBuilder.new(@bounds).build(
                prelude_rows: prelude_rows,
                detail_visible: detail_visible,
                desired_detail_width: desired_detail_width,
                min_primary_width: min_primary_width,
                min_detail_width: min_detail_width,
                stacked_detail_height: stacked_detail_height,
                preferred_width: preferred_width
              )
            end

            def render_frame(layout:, title:, hint: nil, summary_left: nil, summary_right: nil, footer: nil,
                             summary_left_color: nil, summary_right_color: nil)
              render_title(layout, title: title, hint: hint)
              render_divider(layout)
              render_summary(
                layout,
                left: summary_left,
                right: summary_right,
                left_color: summary_left_color,
                right_color: summary_right_color
              )
              render_footer(layout, footer)
            end

            def render_panels(layout:, primary_title:, secondary_title: nil)
              render_panel_heading(layout.primary_panel, primary_title)
              return unless layout.secondary_panel

              render_panel_heading(layout.secondary_panel, secondary_title)
            end

            private

            def render_title(layout, title:, hint:)
              start_col = layout.shell_indent
              title_col = start_col + brand_width + 2
              hint_width = render_hint(layout, start_col, hint)
              max_title_width = title_width(layout, start_col, title_col, hint_width)

              @surface.write(@bounds, 1, start_col, @tokens.brand_badge)
              @surface.write(
                @bounds,
                1,
                title_col,
                "#{@tokens.heading}#{truncate(title.to_s, max_title_width)}#{@tokens.reset}"
              )
            end

            def render_divider(layout)
              line = '─' * [layout.shell_width, 1].max
              @surface.write(@bounds, 2, layout.shell_indent, "#{@tokens.divider}#{line}#{@tokens.reset}")
            end

            def render_summary(layout, left:, right:, left_color:, right_color:)
              return if left.to_s.empty? && right.to_s.empty?

              @status_renderer.render_status(
                row: layout.summary_row,
                indent: layout.shell_indent,
                left: left.to_s,
                right: right.to_s,
                width: layout.shell_width,
                left_color: left_color || @tokens.dim,
                right_color: right_color || @tokens.dim
              )
            end

            def render_footer(layout, footer)
              text = footer.to_s.strip
              return if text.empty?

              clipped = truncate(text, layout.shell_width)
              @surface.write(
                @bounds,
                layout.footer_row,
                layout.shell_indent,
                "#{@tokens.dim}#{clipped}#{@tokens.reset}"
              )
            end

            def render_panel_heading(panel, title)
              heading = clipped_heading(panel, title)
              return if heading.empty?

              @surface.write(@bounds, panel.frame.y, panel.frame.x, panel_heading_line(panel.frame.width, heading))
            end

            def brand_width
              visible_width(BRAND_LABEL)
            end

            def render_hint(layout, start_col, hint)
              hint_text = hint.to_s.strip
              return 0 if hint_text.empty?

              hint_width = visible_width(hint_text)
              hint_col = start_col + layout.shell_width - hint_width + 1
              @surface.write(@bounds, 1, hint_col, "#{@tokens.dim}#{hint_text}#{@tokens.reset}")
              hint_width
            end

            def title_width(layout, start_col, title_col, hint_width)
              available_width = layout.shell_width - (title_col - start_col)
              return [available_width, 1].max if hint_width.zero?

              [available_width - hint_width - 3, 1].max
            end

            def clipped_heading(panel, title)
              return '' unless panel

              truncate(title.to_s.strip.upcase, panel.frame.width)
            end

            def panel_heading_line(width, heading)
              "#{@tokens.accent}#{truncate(heading, width)}#{@tokens.reset}"
            end

            def truncate(text, width)
              Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, width.to_i)
            end

            def visible_width(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end
          end
        end
      end
    end
  end
end
