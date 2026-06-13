# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/text_utils'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require 'shoko/shared/terminal/text_sanitizer'
require 'shoko/shared/terminal/ansi'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Detailed view for a selected annotation with readable sections.
          class AnnotationDetailScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include AnnotationScreenRendering

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              annotation = selected_annotation
              view = annotation ? AnnotationView.new(annotation) : nil

              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Annotation Detail', hint: 'O open  E edit  D delete  ESC back')
              frame.render_divider

              unless view
                render_empty(surface, bounds)
                frame.render_footer(text: 'No annotation selected')
                return
              end

              layout = compute_layout(bounds)
              render_status(surface, bounds, layout, view)
              render_sections(surface, bounds, layout, view)
              frame.render_footer(text: footer_text(view))
            end

            def preferred_height(_available_height)
              :fill
            end

            # Section rendering helpers for annotation detail screens.
            include Adapters::Ui::Constants::Ui

            SectionContext = Data.define(:surface, :bounds, :row, :indent, :width, :title, :lines, :budget, :prefix)

            private

            def render_empty(surface, bounds)
              MenuDesign::StatusRenderer.new(surface, bounds).render_empty(
                row: bounds.height / 2,
                indent: 2,
                message: 'Select an annotation from the list to inspect details.',
                color: COLOR_TEXT_DIM
              )
            end

            def render_status(surface, bounds, layout, annotation)
              left = "Book • #{resolve_book_label}"
              right_parts = [
                "Ch #{annotation.chapter_index || '—'}",
              ].compact

              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:content_indent],
                left: truncate_text(left, [layout[:content_width] - 10, 8].max),
                right: right_parts.join('  •  '),
                width: layout[:content_width],
                left_color: COLOR_TEXT_DIM,
                right_color: COLOR_TEXT_DIM
              )
            end

            def wrap_block(text, width, empty:)
              clean = safe_text(text.to_s)
              clean = empty if clean.strip.empty?
              wrap_text(clean, [width, 8].max)
            end

            def compute_layout(bounds)
              content_width = MenuDesign::Layout.centered_content_width(
                bounds,
                preferred: 104,
                min: 52,
                horizontal_padding: 8
              )
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)

              {
                status_row: 3,
                content_indent: indent,
                content_width: content_width,
                content_top: 5,
                content_bottom: bounds.height - 2,
              }
            end

            def footer_text(annotation)
              saved = annotation.formatted_date.to_s.strip
              saved = 'unknown' if saved.empty?
              "Saved #{saved}"
            end

            def selected_annotation
              ann = menu_state_reader&.selected_annotation
              ann if ann.is_a?(Hash)
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text, preserve_newlines: false, preserve_tabs: false)
            end

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
