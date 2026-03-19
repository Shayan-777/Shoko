# frozen_string_literal: true

require_relative '../../../../shared/terminal/text_metrics'
require_relative 'theme_tokens'

module Shoko
  module Adapters
    module Ui
      module Components
        module MenuDesign
          # Consistent search field rendering for menu list screens.
          class SearchFieldRenderer
            def initialize(surface, bounds, tokens: ThemeTokens.new)
              @surface = surface
              @bounds = bounds
              @tokens = tokens
            end

            def render(label:, query:, cursor:, row:, indent:, width:, active:, compact: false)
              label_text = label.to_s.upcase
              if compact
                render_compact(label_text, query: query, cursor: cursor, row: row, indent: indent, width: width,
                                           active: active)
              else
                render_stacked(label_text, query: query, cursor: cursor, row: row, indent: indent, width: width,
                                           active: active)
              end
            end

            private

            def render_stacked(label_text, query:, cursor:, row:, indent:, width:, active:)
              @surface.write(@bounds, row, indent, "#{@tokens.dim}#{label_text}#{@tokens.reset}")

              line = search_line(query, cursor, width, active)
              @surface.write(@bounds, row + 1, indent, line)
            end

            def render_compact(label_text, query:, cursor:, row:, indent:, width:, active:)
              label = "#{@tokens.dim}#{label_text}#{@tokens.reset} "
              label_width = Shoko::Shared::Terminal::TextMetrics.visible_length(label_text) + 1
              field_width = [width.to_i - label_width, 10].max
              line = "#{label}#{search_line(query, cursor, field_width, active)}"
              @surface.write(@bounds, row, indent, line)
            end

            def search_line(query, cursor, width, active)
              usable = [width.to_i, 10].max
              inner = [usable - 4, 1].max
              body = search_body(query, cursor, inner)
              search_frame(body, active)
            end

            def search_body(query, cursor, width)
              text = query.to_s.dup
              cursor_index = cursor.to_i.clamp(0, text.length)
              text.insert(cursor_index, @tokens.cursor_glyph)
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(text, width)
              Shoko::Shared::Terminal::TextMetrics.pad_right(clipped, width)
            end

            def search_frame(body, active)
              border_color = active ? @tokens.accent : @tokens.divider
              text_color = active ? @tokens.primary : @tokens.dim
              "#{border_color}[#{@tokens.reset} #{text_color}#{body}#{@tokens.reset} #{border_color}]#{@tokens.reset}"
            end
          end
        end
      end
    end
  end
end
