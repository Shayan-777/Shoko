# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Section rendering helpers for annotation detail screens.
          module AnnotationDetailScreenSectionSupport
            include Adapters::Ui::Constants::Ui

            SectionContext = Data.define(:surface, :bounds, :row, :indent, :width, :title, :lines, :budget, :prefix)

            private

            def render_sections(surface, bounds, layout, annotation)
              sections = section_contexts(surface, bounds, layout, annotation)
              row = render_section(sections.fetch(:quote))
              render_section(sections.fetch(:note).with(row: row + 1))
            end

            def render_section(section)
              render_section_heading(section)
              render_section_lines(section)
              section.row + 2 + [section.budget, 1].max
            end

            def section_contexts(surface, bounds, layout, annotation)
              base_context = { surface: surface, bounds: bounds, layout: layout, annotation: annotation }
              budgets = section_budgets(layout)
              {
                quote: quote_section_context(base_context, budgets[:quote]),
                note: note_section_context(base_context, budgets[:note]),
              }
            end

            def section_context(surface, bounds, layout, title:, lines:, budget:, prefix:)
              SectionContext.new(
                surface: surface,
                bounds: bounds,
                row: layout[:content_top],
                indent: layout[:content_indent],
                width: layout[:content_width],
                title: title,
                lines: lines,
                budget: budget,
                prefix: prefix
              )
            end

            def quote_section_context(base_context, budget)
              section_context(
                base_context.fetch(:surface),
                base_context.fetch(:bounds),
                base_context.fetch(:layout),
                title: 'Selected Text',
                lines: wrapped_quote_lines(base_context),
                budget: budget,
                prefix: '│ '
              )
            end

            def note_section_context(base_context, budget)
              section_context(
                base_context.fetch(:surface),
                base_context.fetch(:bounds),
                base_context.fetch(:layout),
                title: 'Note',
                lines: wrapped_note_lines(base_context),
                budget: budget,
                prefix: '  '
              )
            end

            def wrapped_quote_lines(base_context)
              annotation = base_context.fetch(:annotation)
              layout = base_context.fetch(:layout)
              wrap_block(annotation.text, layout[:content_width] - 3, empty: 'No selected text.')
            end

            def wrapped_note_lines(base_context)
              annotation = base_context.fetch(:annotation)
              layout = base_context.fetch(:layout)
              wrap_block(annotation.note, layout[:content_width] - 3, empty: 'No note added yet.')
            end

            def section_budgets(layout)
              available_rows = [layout[:content_bottom] - layout[:content_top] + 1, 6].max
              quote_budget = (available_rows * 0.55).floor.clamp(4, available_rows - 3)
              note_budget = [available_rows - quote_budget - 3, 2].max
              { quote: quote_budget, note: note_budget }
            end

            def render_section_heading(section)
              title_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}"
              reset = Shoko::Shared::Terminal::Ansi::RESET
              section.surface.write(
                section.bounds,
                section.row,
                section.indent,
                "#{title_style}#{section.title}#{reset}"
              )
              section.surface.write(
                section.bounds,
                section.row + 1,
                section.indent,
                "#{COLOR_TEXT_DIM}#{'─' * section.width}#{reset}"
              )
            end

            def render_section_lines(section)
              clipped_lines(section).each_with_index do |line, offset|
                content = truncate_text("#{section.prefix}#{line}", section.width)
                section.surface.write(
                  section.bounds,
                  section.row + 2 + offset,
                  section.indent,
                  pad_right(content, section.width)
                )
              end
            end

            def clipped_lines(section)
              return [] if section.budget <= 0
              return section.lines.first(section.budget) if section.lines.length <= section.budget

              clipped = section.lines.first(section.budget)
              clipped[-1] = truncate_text('…', [clipped[-1].to_s.length, 1].max)
              clipped
            end
          end
        end
      end
    end
  end
end
