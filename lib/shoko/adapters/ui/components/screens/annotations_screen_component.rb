# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../../../../shared/terminal/ansi'
require_relative '../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Annotation browser with list + contextual preview workspace.
          class AnnotationsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            SPLIT_MIN_WIDTH = 100
            PREVIEW_WIDTH_MIN = 34
            PREVIEW_WIDTH_MAX = 42
            PREVIEW_GAP = 3

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @reader_state_reader = nil
              @menu_state_reader = nil
              @selected = 0
              @list = []
              @mode = :book
              @current_book_path = nil
              @current_annotation = nil
              refresh_data
            end

            attr_reader :selected, :current_annotation, :current_book_path

            def selected=(value)
              @selected = [value, 0].max
              update_current_annotation
            end

            def navigate(direction)
              annotations = current_annotations
              return if annotations.empty?

              case direction
              when :up then @selected = [@selected - 1, 0].max
              when :down then @selected = [@selected + 1, annotations.length - 1].min
              end

              update_current_annotation
            end

            def refresh_data
              prev_selected = @selected
              load_annotations_for_mode
              clamp_selection(prev_selected)
              update_current_annotation
            end

            def do_render(surface, bounds)
              refresh_data
              annotations = current_annotations
              layout = compute_layout(bounds, split_allowed: annotations.any?)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              render_frame(frame)
              return render_empty_annotations(surface, bounds, frame) if annotations.empty?

              render_annotations_workspace(surface, bounds, layout, annotations.length)
              frame.render_footer(text: footer_text(annotations.length))
            end

            def preferred_height(_available_height)
              :fill
            end

            AnnotationRow = Data.define(:row, :annotation, :selected, :columns, :indent, :index)
            UI = Adapters::Ui::Constants::Ui

            private

            def render_frame(frame)
              frame.render_title(title: 'Annotations', hint: 'ENTER open  E edit  D delete  ESC back')
              frame.render_divider
            end

            def render_empty_annotations(surface, bounds, frame)
              render_empty_state(surface, bounds)
              frame.render_footer(text: 'No annotations yet')
            end

            def render_annotations_workspace(surface, bounds, layout, total)
              render_status_row(surface, bounds, layout, total)
              render_list(surface, bounds, layout, current_annotations)
              render_preview_area(
                surface: surface,
                bounds: bounds,
                layout: layout,
                annotation: current_annotation,
                total: total
              )
            end

            def render_preview_area(surface:, bounds:, layout:, annotation:, total:)
              if layout[:preview_panel]
                render_preview(surface, bounds, preview_context(layout, annotation, total))
              else
                render_compact_preview(surface, bounds, layout, annotation)
              end
            end

            def current_annotations
              @list || []
            end

            def load_annotations_for_mode
              path = reader_state_reader&.book_path
              if path && !path.to_s.empty?
                load_book_annotations(path)
              else
                load_all_annotations
              end
            end

            def load_book_annotations(path)
              @mode = :book
              @current_book_path = path
              raw = reader_state_reader&.annotations || []
              @list = normalize_list(raw).map { |a| a.merge(book_path: path) }
            end

            def load_all_annotations
              @mode = :all
              mapping = menu_state_reader&.annotations_all || {}
              @list = mapping.flat_map do |book_path, items|
                normalize_list(items).map { |a| a.merge(book_path: book_path) }
              end
            end

            def reader_state_reader
              return @reader_state_reader if @reader_state_reader

              @reader_state_reader = @dependencies&.reader_state_reader
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def clamp_selection(prev_selected)
              upper = [current_annotations.length - 1, 0].max
              @selected = prev_selected.clamp(0, upper)
            end

            def update_current_annotation
              annotations = current_annotations
              @current_annotation = annotations[@selected] if @selected < annotations.length
              return unless @current_annotation

              book_path = @current_annotation[:book_path]
              @current_book_path = book_path if book_path
            end

            def render_empty_state(surface, bounds)
              MenuDesign::StatusRenderer.new(surface, bounds).render_empty(
                row: bounds.height / 2,
                indent: 2,
                message: 'No annotations found. Create one while reading to populate this workspace.',
                color: COLOR_TEXT_DIM
              )
            end

            def normalize_list(raw)
              (raw || []).map do |a|
                annotation = normalize_annotation(a)
                {
                  text: annotation[:text],
                  note: annotation[:note],
                  id: annotation[:id],
                  range: annotation[:range],
                  chapter_index: annotation[:chapter_index],
                  created_at: annotation[:created_at],
                  updated_at: annotation[:updated_at],
                  page_current: annotation[:page_current],
                  page_total: annotation[:page_total],
                  page_mode: annotation[:page_mode],
                }
              end
            end

            def normalize_annotation(annotation)
              Shoko::Shared::HashNormalizer.deep_symbolize(annotation) || {}
            end

            def created_at_label(value)
              text = value.to_s
              saved = text.split('T', 2).first.to_s
              saved.empty? ? '—' : saved
            end

            # Layout and text-formatting helpers for annotations workspace rendering.
            def compute_layout(bounds, split_allowed:)
              content_width = centered_content_width(bounds)
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)
              list_width, preview_panel = preview_layout(bounds, content_width, indent, split_allowed)

              list_rows(bounds).merge(
                list_indent: indent,
                list_render_width: list_width,
                list_columns: compute_columns(list_width),
                preview_panel: preview_panel
              )
            end

            def centered_content_width(bounds)
              MenuDesign::Layout.centered_content_width(bounds, preferred: 108, min: 58, horizontal_padding: 8)
            end

            def list_rows(bounds)
              {
                status_row: 3,
                header_row: 4,
                list_start_row: 6,
                list_bottom_row: bounds.height - 2,
                list_height: [bounds.height - 7, 1].max,
              }
            end

            def preview_layout(bounds, content_width, indent, split_allowed)
              return [content_width, nil] unless split_preview?(bounds, content_width, split_allowed)

              preview_width = (content_width * 0.35).to_i.clamp(
                AnnotationsScreenComponent::PREVIEW_WIDTH_MIN,
                AnnotationsScreenComponent::PREVIEW_WIDTH_MAX
              )
              list_width = content_width - preview_width - AnnotationsScreenComponent::PREVIEW_GAP
              return [content_width, nil] if list_width < 40

              [list_width, build_preview_panel(bounds, indent, list_width, preview_width)]
            end

            def split_preview?(bounds, content_width, split_allowed)
              split_allowed &&
                content_width >= AnnotationsScreenComponent::SPLIT_MIN_WIDTH &&
                bounds.height >= 20
            end

            def build_preview_panel(bounds, indent, list_width, preview_width)
              {
                x: indent + list_width + AnnotationsScreenComponent::PREVIEW_GAP,
                y: 4,
                width: preview_width,
                height: [bounds.height - 6, 6].max,
              }
            end

            def compute_columns(list_width)
              idx = 4
              chapter = 4
              note = 6
              saved = 10
              gap = 2
              excerpt = [list_width - idx - chapter - note - saved - (gap * 4), 12].max
              { idx: idx, chapter: chapter, excerpt: excerpt, note: note, saved: saved }
            end

            def footer_text(count)
              "#{count} annotations"
            end

            def format_chapter(chapter_index)
              chapter_index.nil? ? '—' : chapter_index.to_i.to_s
            end

            def one_line(text, fallback:)
              raw = safe_text(text.to_s.tr("\n", ' ').strip)
              raw.empty? ? fallback : raw
            end

            def build_book_label(all_mode:)
              return sanitize_filename(File.basename(@current_book_path)) if @current_book_path

              all_mode ? 'All Books' : 'No book selected'
            end

            def build_book_cell(annotation, width)
              book = annotation[:book_path] ? sanitize_filename(File.basename(annotation[:book_path])) : ''
              pad_right(truncate_text(book, width), width)
            end

            def sanitize_filename(raw)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(raw, preserve_newlines: false, preserve_tabs: false)
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text, preserve_newlines: false, preserve_tabs: false)
            end

            def render_status_row(surface, bounds, layout, count)
              scope = annotation_scope_label
              right = "#{selected + 1}/#{count} selected"
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:list_indent],
                left: truncate_text(scope, [layout[:list_render_width] - 8, 8].max),
                right: right,
                width: layout[:list_render_width],
                left_color: UI::COLOR_TEXT_DIM,
                right_color: UI::COLOR_TEXT_DIM
              )
            end

            def annotation_scope_label
              return "Book • #{build_book_label(all_mode: false)}" if @mode == :book

              'Library • All books'
            end

            def render_list(surface, bounds, layout, annotations)
              cols = layout[:list_columns]
              render_list_header(surface, bounds, layout, cols)
              annotation_rows(layout, annotations, cols).each do |row|
                render_annotation_row(surface, bounds, row)
              end
            end

            def render_list_header(surface, bounds, layout, cols)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: layout[:header_row],
                indent: layout[:list_indent],
                headers: ['#', 'Ch', 'Excerpt', 'Note', 'Saved'],
                widths: [cols[:idx], cols[:chapter], cols[:excerpt], cols[:note], cols[:saved]],
                divider_char: '─'
              )
            end

            def annotation_rows(layout, annotations, cols)
              start_index, visible = Ui::ListHelpers.slice_visible(annotations, layout[:list_height], selected)
              visible.each_with_index.filter_map do |annotation, offset|
                row = layout[:list_start_row] + offset
                next if row > layout[:list_bottom_row]

                AnnotationRow.new(
                  row: row,
                  annotation: annotation,
                  selected: (start_index + offset) == selected,
                  columns: cols,
                  indent: layout[:list_indent],
                  index: start_index + offset
                )
              end
            end

            def render_annotation_row(surface, bounds, row)
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.indent,
                cells: row_cells(row),
                widths: [row.columns[:idx], row.columns[:chapter], row.columns[:excerpt], row.columns[:note],
                         row.columns[:saved]],
                selected: row.selected
              )
            end

            def row_cells(row)
              [
                index_cell(row),
                chapter_cell(row),
                excerpt_cell_text(row),
                note_cell_text(row),
                saved_cell_text(row),
              ]
            end

            def index_cell(row)
              pad_left((row.index + 1).to_s, row.columns[:idx])
            end

            def chapter_cell(row)
              pad_right(format_chapter(row.annotation[:chapter_index]), row.columns[:chapter])
            end

            def excerpt_cell_text(row)
              text = truncate_text(excerpt_cell(row.annotation), row.columns[:excerpt])
              pad_right(text, row.columns[:excerpt])
            end

            def note_cell_text(row)
              pad_right(note_cell(row.annotation), row.columns[:note])
            end

            def saved_cell_text(row)
              pad_right(saved_cell(row.annotation), row.columns[:saved])
            end

            def excerpt_cell(annotation)
              one_line(annotation[:text], fallback: 'No selected text')
            end

            def note_cell(annotation)
              annotation[:note].to_s.strip.empty? ? '—' : 'yes'
            end

            def saved_cell(annotation)
              created_at_label(annotation[:created_at])
            end

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
