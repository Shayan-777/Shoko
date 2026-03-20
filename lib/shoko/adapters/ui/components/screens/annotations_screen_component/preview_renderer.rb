# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Preview-panel and compact-preview rendering for annotations.
          module AnnotationsScreenComponentPreviewRenderer
            UI = Adapters::Ui::Constants::Ui

            private

            def render_preview(surface, bounds, panel)
              return unless panel && panel[:annotation]

              render_preview_header(surface, bounds, panel)
              write_preview_body(surface, bounds, panel, preview_lines(panel))
            end

            def render_preview_header(surface, bounds, panel)
              heading = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::COLOR_TEXT_ACCENT}PREVIEW#{Shoko::Shared::Terminal::Ansi::RESET}"
              divider = "#{UI::COLOR_TEXT_DIM}#{'─' * panel[:width]}#{Shoko::Shared::Terminal::Ansi::RESET}"
              surface.write(bounds, panel[:y], panel[:x], heading)
              surface.write(bounds, panel[:y] + 1, panel[:x], divider)
            end

            def write_preview_body(surface, bounds, panel, lines)
              body_start = panel[:y] + 2
              max_lines = [panel[:height] - 2, 1].max
              fit_lines(lines, max_lines).each_with_index do |line, offset|
                surface.write(bounds,
                              body_start + offset,
                              panel[:x],
                              pad_right(truncate_text(line, panel[:width]), panel[:width]))
              end
            end

            def preview_lines(panel)
              annotation = panel[:annotation]
              [
                "Selection #{selected + 1} of #{panel[:total]}",
                "Chapter #{format_chapter(annotation[:chapter_index])}",
                "Book #{truncate_text(build_book_cell(annotation, panel[:width] - 6), panel[:width] - 6)}",
                '',
                'Quote',
                *quote_preview_lines(annotation, panel),
                '',
                'Note',
                *note_preview_lines(annotation, panel),
              ]
            end

            def quote_preview_lines(annotation, panel)
              preview_body_lines(annotation[:text], panel[:width], empty_fallback: '—')
            end

            def note_preview_lines(annotation, panel)
              preview_body_lines(annotation[:note], panel[:width], empty_fallback: 'No note')
            end

            def preview_body_lines(text, width, empty_fallback:)
              source = text.to_s.strip
              source = empty_fallback if source.empty?
              wrap_text(safe_text(source), width - 2).first(4).map { |line| "  #{line}" }
            end

            def render_compact_preview(surface, bounds, layout, annotation)
              return unless annotation

              row = bounds.height - 2
              text = "Preview: #{one_line(annotation[:text], fallback: 'No selected text')}"
              surface.write(
                bounds,
                row,
                layout[:list_indent],
                "#{UI::COLOR_TEXT_DIM}#{truncate_text(text, layout[:list_render_width])}#{Shoko::Shared::Terminal::Ansi::RESET}"
              )
            end

            def preview_context(layout, annotation, total)
              panel = layout[:preview_panel]
              return unless panel

              panel.merge(annotation: annotation, total: total)
            end

            def fit_lines(lines, max_lines)
              return [] if max_lines <= 0
              return lines.first(max_lines) if lines.length <= max_lines

              clipped = lines.first(max_lines)
              clipped[-1] = truncate_text('…', [clipped[-1].to_s.length, 1].max)
              clipped
            end
          end
        end
      end
    end
  end
end
