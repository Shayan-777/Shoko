# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Rendering helpers for the menu annotation edit screen.
          module AnnotationEditScreenRenderSupport
            include Adapters::Ui::Constants::Ui

            EditorRenderContext = Data.define(:surface, :bounds, :layout, :lines, :cursor_state)
            EditorLineContext = Data.define(:surface, :bounds, :layout, :index, :line_text, :cursor_state)

            private

            def render_quote_context(surface, bounds, layout, annotation)
              render_section_heading(
                surface,
                bounds,
                row: layout[:quote_heading_row],
                indent: layout[:content_indent],
                width: layout[:content_width],
                title: 'Selected Text Context'
              )

              visible_quote_lines(annotation, layout).each_with_index do |line, index|
                row = layout[:quote_start_row] + index
                content = truncate_text("│ #{line}", layout[:content_width])
                surface.write(bounds, row, layout[:content_indent], pad_right(content, layout[:content_width]))
              end
            end

            def render_editor(surface, bounds, layout)
              render_editor_heading(surface, bounds, layout)
              render_editor_lines(
                EditorRenderContext.new(
                  surface: surface,
                  bounds: bounds,
                  layout: layout,
                  lines: prepared_editor_lines(layout),
                  cursor_state: prepared_cursor_state(layout)
                )
              )
            end

            def compute_layout(bounds)
              content_width = MenuDesign::Layout.centered_content_width(
                bounds,
                preferred: 110,
                min: 58,
                horizontal_padding: 8
              )

              {
                status_row: 3,
                content_indent: MenuDesign::Layout.centered_indent(bounds, content_width),
                content_width: content_width,
              }.merge(quote_layout(bounds)).merge(editor_layout(bounds))
            end

            def visible_quote_lines(annotation, layout)
              quote = annotation.text.to_s.strip
              quote = 'No selected text.' if quote.empty?
              wrap_text(safe_text(quote), [layout[:content_width] - 2, 8].max).first(layout[:quote_lines_visible])
            end

            def render_section_heading(surface, bounds, row:, indent:, width:, title:)
              heading_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}"
              reset = Shoko::Shared::Terminal::Ansi::RESET
              surface.write(bounds, row, indent, "#{heading_style}#{title}#{reset}")
              surface.write(bounds, row + 1, indent, "#{COLOR_TEXT_DIM}#{'─' * width}#{reset}")
            end

            def quote_layout(bounds)
              {
                quote_heading_row: 4,
                quote_divider_row: 5,
                quote_start_row: 6,
                quote_lines_visible: bounds.height >= 30 ? 4 : 3,
              }
            end

            def editor_layout(bounds)
              quote_info = quote_layout(bounds)
              editor_heading = quote_info[:quote_start_row] + quote_info[:quote_lines_visible] + 1
              editor_divider = editor_heading + 1
              editor_start = editor_divider + 1
              editor_bottom = bounds.height - 2

              {
                editor_heading_row: editor_heading,
                editor_divider_row: editor_divider,
                editor_start_row: editor_start,
                editor_height: [editor_bottom - editor_start + 1, 3].max,
              }
            end

            def editor_text_width(layout)
              [layout[:content_width] - self.class::GUTTER_WIDTH - 1, 8].max
            end

            def render_editor_heading(surface, bounds, layout)
              render_section_heading(
                surface,
                bounds,
                row: layout[:editor_heading_row],
                indent: layout[:content_indent],
                width: layout[:content_width],
                title: 'Note Editor'
              )
            end

            def prepared_editor_text(layout)
              @editor_text_width = editor_text_width(layout)
              edit_state.text.to_s
            end

            def prepared_editor_lines(layout)
              text = prepared_editor_text(layout)
              Ui::AnnotationMarkup::Styler.new(text).render_lines(@editor_text_width)
            end

            def prepared_cursor_state(layout)
              text = prepared_editor_text(layout)
              styler = Ui::AnnotationMarkup::Styler.new(text)
              editor_cursor_state(styler, text, layout)
            end

            def editor_cursor_state(styler, text, layout)
              cursor_index = edit_state.cursor(text)
              cursor_line, cursor_col = styler.cursor_position(cursor_index, @editor_text_width)
              @editor_scroll_top = compute_scroll_top(cursor_line, layout[:editor_height])
              {
                line: cursor_line,
                col: cursor_col,
                visible_line: cursor_line - @editor_scroll_top,
              }
            end

            def visible_editor_lines(lines, layout)
              visible = lines[@editor_scroll_top, layout[:editor_height]] || []
              Array.new(layout[:editor_height]) { |index| visible[index].to_s }
            end

            def render_editor_lines(context)
              visible_editor_lines(context.lines, context.layout).each_with_index do |line_text, index|
                render_editor_line(
                  EditorLineContext.new(
                    surface: context.surface,
                    bounds: context.bounds,
                    layout: context.layout,
                    index: index,
                    line_text: line_text,
                    cursor_state: context.cursor_state
                  )
                )
              end
            end

            def render_editor_line(context)
              row, gutter, padded = editor_line_output(context)
              context.surface.write(
                context.bounds,
                row,
                context.layout[:content_indent],
                editor_line_shell(gutter, padded)
              )
            end

            def editor_line_text(line_text, index, cursor_state)
              display = "#{line_text}#{Ui::AnnotationMarkup::STYLE_RESET}"
              return display unless index == cursor_state[:visible_line]

              inline_cursor_text(
                display,
                cursor_state[:col],
                width: @editor_text_width,
                style_prefix: SELECTION_HIGHLIGHT,
                restore_prefix: COLOR_TEXT_PRIMARY
              )
            end

            def editor_line_output(context)
              absolute_line = @editor_scroll_top + context.index
              row = context.layout[:editor_start_row] + context.index
              gutter = pad_left((absolute_line + 1).to_s, self.class::GUTTER_WIDTH - 1)
              content = editor_line_text(context.line_text, context.index, context.cursor_state)
              [row, gutter, pad_right(content, @editor_text_width)]
            end

            def editor_line_shell(gutter, padded)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              "#{COLOR_TEXT_DIM}#{gutter} #{reset}#{COLOR_TEXT_PRIMARY}#{padded}#{reset}"
            end
          end
        end
      end
    end
  end
end
