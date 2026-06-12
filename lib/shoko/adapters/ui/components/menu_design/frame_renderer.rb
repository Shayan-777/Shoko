# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Canonical top/bottom shell renderer for menu-mode screens.
          class FrameRenderer
            SHELL_MAX_WIDTH = 98
            SHELL_MIN_WIDTH = 40
            SHELL_MARGIN = 4
            TitleRow = Data.define(:row, :shell_indent, :shell_width, :content_indent)

            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
            end

            def render_title(title:, hint: nil, row: 1, indent: 2)
              shell = shell_metrics
              title_row = TitleRow.new(
                row: row,
                shell_indent: shell[:indent],
                shell_width: shell[:width],
                content_indent: indent
              )
              write_title_row(title_row, title.to_s)
              write_hint(row, shell[:indent], shell[:width], hint) if hint && !hint.to_s.strip.empty?
            end

            def render_divider(row: 2, indent: 1, width: nil, char: '─')
              shell = divider_shell(indent, width)
              line = char * [shell[:width], 1].max
              @surface.write(@bounds, row, shell[:indent], "#{@tokens.divider}#{line}#{@tokens.reset}")
            end

            def render_footer(text: nil, row: nil, indent: 2)
              row ||= @bounds.height - 1
              return if text.to_s.strip.empty?

              shell = shell_metrics
              inner = [shell[:width] - 4, 1].max
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, inner)
              content_col = [shell[:indent], indent].max
              @surface.write(@bounds, row, content_col, "#{@tokens.dim}#{clipped}#{@tokens.reset}")
            end

            private

            def shell_metrics
              width = [@bounds.width - SHELL_MARGIN, SHELL_MAX_WIDTH].min
              width = [width, SHELL_MIN_WIDTH].max
              width = [width, @bounds.width - 2].min
              indent = ((@bounds.width - width) / 2).floor
              indent = indent.clamp(2, [@bounds.width - width, 2].max)
              { indent: indent, width: width }
            end

            def divider_shell(indent, width)
              return shell_metrics if full_width_divider?(indent, width)

              usable = width || (@bounds.width - indent + 1)
              { indent: indent, width: [usable, 1].max }
            end

            def write_title_row(title_row, title)
              brand = @tokens.brand_badge
              content_col, title_col, clipped_title = title_layout(title_row, title)
              @surface.write(@bounds, title_row.row, content_col, brand)
              @surface.write(@bounds, title_row.row, title_col, "#{@tokens.heading}#{clipped_title}#{@tokens.reset}")
            end

            def title_layout(title_row, title)
              content_col = [title_row.shell_indent, title_row.content_indent].max
              title_col = content_col + Shoko::Shared::Terminal::TextMetrics.visible_length('SHOKO') + 2
              max_title_w = [title_row.shell_width - (title_col - title_row.shell_indent) - 2, 1].max
              clipped_title = Shoko::Shared::Terminal::TextMetrics.truncate_to(title, max_title_w)
              [content_col, title_col, clipped_title]
            end

            def write_hint(row, shell_indent, shell_width, hint)
              hint_text = hint.to_s
              hint_width = Shoko::Shared::Terminal::TextMetrics.visible_length(hint_text)
              min_col = shell_indent + 20
              max_col = shell_indent + shell_width - hint_width - 1
              col = [max_col, min_col].max
              @surface.write(@bounds, row, col, "#{@tokens.dim}#{hint_text}#{@tokens.reset}")
            end

            def full_width_divider?(indent, width)
              indent.to_i <= 1 && width.nil?
            end
          end
        end
      end
    end
  end
end
