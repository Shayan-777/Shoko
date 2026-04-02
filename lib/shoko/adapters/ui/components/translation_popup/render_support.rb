# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/overlay_layout'

module Shoko
  module Adapters
    module Ui
      module Components
        class TranslationPopupComponent < BaseComponent
          module TranslationPopup
            # Rendering helpers for the translation popup frame and body layout.
            module RenderSupport
              private

              def overlay_layout(bounds)
                width = @overlay_sizing.width_for(bounds.width)
                height = @overlay_sizing.height_for(bounds.height)
                Ui::OverlayLayout.centered(bounds, width: width, height: height)
              end

              def render_frame(context)
                layout = context[:layout]
                render_horizontal_border(context, row: layout.origin_y, left: '┌', right: '┐')
                render_vertical_borders(context)
                render_horizontal_border(
                  context,
                  row: layout.origin_y + layout.height - 1,
                  left: '└',
                  right: '┘'
                )
              end

              def render_content(context)
                row = context[:row]
                write_text(context, row: row, col: context[:x], text: "#{header_fg}Translation#{reset}")
                row += 1
                write_text(context, row: row, col: context[:x], text: metadata_line(context[:width]))
                row += 2

                visible_content_lines(context[:width]).each do |line|
                  write_text(context, row: row, col: context[:x], text: line)
                  row += 1
                end

                render_footer(context)
              end

              def visible_content_lines(width)
                content_lines(width).drop(@scroll_offset).first(@last_visible_body_lines)
              end

              def render_footer(context)
                layout = context[:layout]
                footer_row = layout.origin_y + layout.height - 2
                write_text(context, row: footer_row, col: context[:x], text: footer_text(context[:width]))
              end

              def render_vertical_borders(context)
                layout = context[:layout]
                rows = (layout.origin_y + 1)...(layout.origin_y + layout.height - 1)
                rows.each do |row|
                  write_text(context, row: row, col: layout.origin_x, text: "#{header_fg}│#{reset}")
                  write_text(
                    context,
                    row: row,
                    col: layout.origin_x + layout.width - 1,
                    text: "#{header_fg}│#{reset}"
                  )
                end
              end

              def render_horizontal_border(context, row:, left:, right:)
                layout = context[:layout]
                text = "#{header_fg}#{left}#{'─' * (layout.width - 2)}#{right}#{reset}"
                write_text(context, row: row, col: layout.origin_x, text: text)
              end

              def write_text(context, row:, col:, text:)
                context[:surface].write(context[:bounds], row, col, text)
              end
            end
          end
        end
      end
    end
  end
end
