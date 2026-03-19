# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/terminal/ansi'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Shared table/list row rendering with consistent selection semantics.
          class TableRenderer
            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
            end

            def render_header(row:, indent:, headers:, widths:, gap: 2, divider_char: '─')
              normalized = headers.map { |h| h.to_s.upcase }
              line = compose_line(normalized, widths, gap: gap)
              styled = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{@tokens.panel_heading}#{line}#{@tokens.reset}"
              @surface.write(@bounds, row, indent, styled)
              divider = divider_char * [Shoko::Shared::Terminal::TextMetrics.visible_length(line), 1].max
              @surface.write(@bounds, row + 1, indent, "#{@tokens.divider}#{divider}#{@tokens.reset}")
            end

            def render_row(row:, indent:, cells:, widths:, selected:, gap: 2, pointer: true)
              line = compose_line(cells, widths, gap: gap)
              text = selected ? selected_row_text(line, pointer) : unselected_row_text(line, pointer)
              @surface.write(@bounds, row, indent, text)
            end

            private

            def selected_row_text(line, pointer)
              return @tokens.style_selected(line) if pointer

              "#{Shoko::Shared::Terminal::Ansi::BOLD}#{@tokens.selection_fg}#{line}#{@tokens.reset}"
            end

            def unselected_row_text(line, pointer)
              return @tokens.style_unselected(line) if pointer

              "#{@tokens.primary}#{line}#{@tokens.reset}"
            end

            def compose_line(cells, widths, gap:)
              sep = ' ' * gap
              cells.each_with_index.map do |cell, index|
                width = widths[index].to_i
                text = cell.to_s
                clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(text, width)
                Shoko::Shared::Terminal::TextMetrics.pad_right(clipped, width)
              end.join(sep)
            end
          end
        end
      end
    end
  end
end
