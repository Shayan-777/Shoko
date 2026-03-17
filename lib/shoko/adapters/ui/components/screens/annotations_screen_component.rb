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
              frame.render_title(title: 'Annotations', hint: 'ENTER open  E edit  D delete  ESC back')
              frame.render_divider

              if annotations.empty?
                render_empty_state(surface, bounds)
                frame.render_footer(text: 'No annotations yet')
                return
              end

              render_status_row(surface, bounds, layout, annotations.length)
              render_list(surface, bounds, layout, annotations)
              if layout[:preview_panel]
                render_preview(surface, bounds, layout, current_annotation, annotations.length)
              else
                render_compact_preview(surface, bounds, layout, current_annotation)
              end

              frame.render_footer(text: footer_text(annotations.length))
            end

            def preferred_height(_available_height)
              :fill
            end

            private

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

            def render_status_row(surface, bounds, layout, count)
              scope = if @mode == :book
                        "Book • #{build_book_label(all_mode: false)}"
                      else
                        'Library • All books'
                      end
              right = "#{count} total • #{selected + 1}/#{count}"

              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:list_indent],
                left: truncate_text(scope, [layout[:list_render_width] - 8, 8].max),
                right: right,
                width: layout[:list_render_width],
                left_color: COLOR_TEXT_DIM,
                right_color: COLOR_TEXT_DIM
              )
            end

            def render_list(surface, bounds, layout, annotations)
              cols = layout[:list_columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: layout[:header_row],
                indent: layout[:list_indent],
                headers: ['#', 'Ch', 'Excerpt', 'Note', 'Saved'],
                widths: [cols[:idx], cols[:chapter], cols[:excerpt], cols[:note], cols[:saved]],
                divider_char: '─'
              )

              start_index, visible = Ui::ListHelpers.slice_visible(annotations, layout[:list_height], selected)
              row = layout[:list_start_row]
              visible.each_with_index do |annotation, offset|
                break if row > layout[:list_bottom_row]

                abs_index = start_index + offset
                cells = row_cells(annotation, abs_index, cols)
                MenuDesign::TableRenderer.new(surface, bounds).render_row(
                  row: row,
                  indent: layout[:list_indent],
                  cells: cells,
                  widths: [cols[:idx], cols[:chapter], cols[:excerpt], cols[:note], cols[:saved]],
                  selected: abs_index == selected
                )
                row += 1
              end
            end

            def row_cells(annotation, abs_index, cols)
              excerpt = one_line(annotation[:text], fallback: 'No selected text')
              note_flag = annotation[:note].to_s.strip.empty? ? '—' : 'yes'
              saved = created_at_label(annotation[:created_at])

              [
                pad_left((abs_index + 1).to_s, cols[:idx]),
                pad_right(format_chapter(annotation[:chapter_index]), cols[:chapter]),
                pad_right(truncate_text(excerpt, cols[:excerpt]), cols[:excerpt]),
                pad_right(note_flag, cols[:note]),
                pad_right(saved, cols[:saved]),
              ]
            end

            def render_preview(surface, bounds, layout, annotation, total)
              panel = layout[:preview_panel]
              return unless panel && annotation

              heading = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}PREVIEW#{Shoko::Shared::Terminal::Ansi::RESET}"
              surface.write(bounds, panel[:y], panel[:x], heading)
              divider = "#{COLOR_TEXT_DIM}#{'─' * panel[:width]}#{Shoko::Shared::Terminal::Ansi::RESET}"
              surface.write(bounds, panel[:y] + 1, panel[:x], divider)

              lines = []
              lines << "Selection #{selected + 1} of #{total}"
              lines << "Chapter #{format_chapter(annotation[:chapter_index])}"
              lines << "Book #{truncate_text(build_book_cell(annotation, panel[:width] - 6), panel[:width] - 6)}"
              lines << ''
              lines << 'Quote'
              quote_source = annotation[:text].to_s.strip
              quote_source = '—' if quote_source.empty?
              quote_lines = wrap_text(safe_text(quote_source), panel[:width] - 2)
              quote_lines.first(4).each { |line| lines << "  #{line}" }
              lines << ''
              lines << 'Note'
              note_source = annotation[:note].to_s.strip
              note_source = 'No note' if note_source.empty?
              note_lines = wrap_text(safe_text(note_source), panel[:width] - 2)
              note_lines.first(4).each { |line| lines << "  #{line}" }

              body_start = panel[:y] + 2
              max_lines = [panel[:height] - 2, 1].max
              body = fit_lines(lines, max_lines)
              body.each_with_index do |line, offset|
                surface.write(bounds, body_start + offset, panel[:x],
                              pad_right(truncate_text(line, panel[:width]), panel[:width]))
              end
            end

            def render_compact_preview(surface, bounds, layout, annotation)
              return unless annotation

              row = bounds.height - 2
              summary = one_line(annotation[:text], fallback: 'No selected text')
              text = "Preview: #{summary}"
              surface.write(bounds, row, layout[:list_indent],
                            "#{COLOR_TEXT_DIM}#{truncate_text(text, layout[:list_render_width])}#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def fit_lines(lines, max_lines)
              return [] if max_lines <= 0
              return lines.first(max_lines) if lines.length <= max_lines

              clipped = lines.first(max_lines)
              clipped[-1] = truncate_text('…', [clipped[-1].to_s.length, 1].max)
              clipped
            end

            def compute_layout(bounds, split_allowed:)
              content_width = MenuDesign::Layout.centered_content_width(bounds, preferred: 108, min: 58,
                                                                        horizontal_padding: 8)
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)

              list_width = content_width
              preview_panel = nil
              if split_allowed && content_width >= SPLIT_MIN_WIDTH && bounds.height >= 20
                preview_width = (content_width * 0.35).to_i.clamp(PREVIEW_WIDTH_MIN, PREVIEW_WIDTH_MAX)
                list_candidate = content_width - preview_width - PREVIEW_GAP
                if list_candidate >= 40
                  list_width = list_candidate
                  preview_panel = {
                    x: indent + list_width + PREVIEW_GAP,
                    y: 4,
                    width: preview_width,
                    height: [bounds.height - 6, 6].max,
                  }
                end
              end

              header_row = 4
              list_start_row = 6
              list_bottom_row = bounds.height - 2
              list_height = [list_bottom_row - list_start_row + 1, 1].max

              {
                status_row: 3,
                header_row: header_row,
                list_start_row: list_start_row,
                list_bottom_row: list_bottom_row,
                list_height: list_height,
                list_indent: indent,
                list_render_width: list_width,
                list_columns: compute_columns(list_width),
                preview_panel: preview_panel,
              }
            end

            def compute_columns(list_width)
              idx = 4
              chapter = 4
              note = 6
              saved = 10
              gap = 2
              excerpt = [list_width - idx - chapter - note - saved - (gap * 4), 12].max

              {
                idx: idx,
                chapter: chapter,
                excerpt: excerpt,
                note: note,
                saved: saved,
              }
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
              if @current_book_path
                sanitize_filename(File.basename(@current_book_path))
              else
                all_mode ? 'All Books' : 'No book selected'
              end
            end

            def build_book_cell(annotation, width)
              bp = annotation[:book_path]
              book = bp ? sanitize_filename(File.basename(bp)) : ''
              pad_right(truncate_text(book, width), width)
            end

            def sanitize_filename(raw)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                raw,
                preserve_newlines: false,
                preserve_tabs: false
              )
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                text,
                preserve_newlines: false,
                preserve_tabs: false
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
          end
        end
      end
    end
  end
end
