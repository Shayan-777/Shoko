# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../ui/annotation_markup'
require_relative '../../../terminal/text_metrics'
require_relative '../../../terminal/terminal_sanitizer'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Shared rendering context for annotation screens
      AnnotationRenderContext = Struct.new(
        :surface,
        :bounds,
        :width,
        :height,
        :reset,
        :annotation,
        :book_label,
        keyword_init: true
      )

      # Shared rendering methods for annotation detail and edit screens
      module AnnotationScreenRendering
        private

        def build_annotation_context(surface, bounds, annotation, book_label)
          AnnotationRenderContext.new(
            surface: surface,
            bounds: bounds,
            width: bounds.width,
            height: bounds.height,
            reset: Terminal::ANSI::RESET,
            annotation: annotation,
            book_label: book_label
          )
        end

        def resolve_book_label
          book_path = resolve_menu_reader&.selected_annotation_book
          return 'Unknown Book' unless book_path

          raw = File.basename(book_path)
          Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(
            raw,
            preserve_newlines: false,
            preserve_tabs: false
          )
        end

        def resolve_menu_reader
          return @menu_state_reader if defined?(@menu_state_reader) && @menu_state_reader

          @menu_state_reader = @dependencies&.menu_state_reader if defined?(@dependencies)
          @menu_state_reader
        end

        def render_screen_divider(ctx, row: 2, color: nil)
          color ||= self.class::COLOR_TEXT_DIM
          ctx.surface.write(
            ctx.bounds,
            row,
            1,
            color + ('─' * ctx.width) + ctx.reset
          )
        end

        def render_screen_title(ctx, title_plain, row: 1, col: 2, color: nil)
          color ||= self.class::COLOR_TEXT_ACCENT
          title_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(title_plain)
          title = "#{color}#{title_plain}#{ctx.reset}"
          ctx.surface.write(ctx.bounds, row, col, title)
          title_width
        end

        def render_right_aligned_text(ctx, text_plain, title_width, row: 1, color: nil)
          color ||= self.class::COLOR_TEXT_DIM
          text_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text_plain)
          min_col = 2 + title_width + 2
          right_col = ctx.width - text_width
          col = [right_col, min_col].max
          ctx.surface.write(ctx.bounds, row, col, "#{color}#{text_plain}#{ctx.reset}")
        end

        def render_annotation_text_box(box, ctx, color_prefix:)
          box.render(ctx, drawer: self, color_prefix: color_prefix)
        end

        def build_selected_text_box(ctx, annotation_text, row: 5, height_ratio: 0.35, min_height: 8)
          AnnotationTextBox.new(
            row: row,
            height: [ctx.height * height_ratio, min_height].max.to_i,
            width: ctx.width - 4,
            label: 'Selected Text',
            text: annotation_text
          )
        end
      end

      # Render context for annotations list screen
      AnnotationsListContext = Struct.new(
        :surface, :bounds, :width, :height, :widths, keyword_init: true
      )

      # Column width calculations for annotations list
      AnnotationColumnWidths = Data.define(:idx, :ch, :date, :book, :snippet, :note) do
        def book_col? = book.positive?

        def self.calculate(width, all_mode)
          idx_w = 4
          ch_w = 6
          date_w = 10
          book_w = all_mode ? 12 : 0
          avail = width - (idx_w + ch_w + date_w + book_w + 8)
          snippet_w = (avail * 0.55).to_i
          note_w = avail - snippet_w
          new(idx: idx_w, ch: ch_w, date: date_w, book: book_w, snippet: snippet_w, note: note_w)
        end
      end

      # Rendering methods for annotations list table rows
      module AnnotationsListRendering
        include Adapters::Output::Ui::Constants::UI
        include UI::TextUtils

        RowData = Data.define(:annotation, :abs_idx, :selected_idx) do
          def selected? = abs_idx == selected_idx
        end

        private

        def build_list_context(surface, bounds, all_mode)
          widths = AnnotationColumnWidths.calculate(bounds.width, all_mode)
          AnnotationsListContext.new(
            surface: surface, bounds: bounds,
            width: bounds.width, height: bounds.height, widths: widths
          )
        end

        def render_list_header(ctx, count, book_label)
          reset = Terminal::ANSI::RESET
          left_plain = "📝 Annotations (#{count}) — #{book_label}"
          right_plain = '[Enter] Open • [e] Edit • [d] Delete'

          ctx.surface.write(ctx.bounds, 1, 2, "#{COLOR_TEXT_ACCENT}#{left_plain}#{reset}")
          right_col = compute_header_right_col(ctx.width, left_plain, right_plain)
          ctx.surface.write(ctx.bounds, 1, right_col, "#{COLOR_TEXT_DIM}#{right_plain}#{reset}")
        end

        def compute_header_right_col(width, left_plain, right_plain)
          left_w = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(left_plain)
          right_w = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(right_plain)
          [[width - right_w - 1, 2 + left_w + 2].max, 1].max
        end

        def render_list_column_headers(ctx)
          render_divider(ctx)
          render_column_labels(ctx)
        end

        def render_divider(ctx)
          line = COLOR_TEXT_DIM + ('─' * ctx.width) + Terminal::ANSI::RESET
          ctx.surface.write(ctx.bounds, 2, 1, line)
        end

        def render_column_labels(ctx)
          labels = build_column_labels(ctx.widths)
          ctx.surface.write(ctx.bounds, 3, 1, COLOR_TEXT_DIM + labels + Terminal::ANSI::RESET)
        end

        def build_column_labels(widths)
          parts = column_label_parts(widths)
          parts << "  #{pad_right('Book', widths.book)}" if widths.book_col?
          parts.push('  ', pad_right('Date', widths.date))
          parts.join
        end

        def column_label_parts(widths)
          [
            '  ', pad_right('#', widths.idx),
            '  ', pad_right('Ch', widths.ch),
            '  ', pad_right('Snippet', widths.snippet),
            '  ', pad_right('Note', widths.note)
          ]
        end

        def render_annotation_row(ctx, row, row_data)
          line = build_row_line(row_data.annotation, row_data.selected?, row_data.abs_idx, ctx.widths)
          color = row_data.selected? ? SELECTION_HIGHLIGHT : COLOR_TEXT_PRIMARY
          ctx.surface.write(ctx.bounds, row, 1, color + line + Terminal::ANSI::RESET)
        end

        def build_row_line(annotation, is_selected, abs_idx, widths)
          fields = extract_row_fields(annotation)
          parts = build_row_parts(fields, is_selected, abs_idx, widths)
          append_optional_columns(parts, annotation, fields, widths)
          parts.join
        end

        def build_row_parts(fields, is_selected, abs_idx, widths)
          pointer = is_selected ? '▸' : ' '
          [
            pointer, ' ',
            pad_left((abs_idx + 1).to_s, widths.idx), '  ',
            pad_right(fields[:chapter], widths.ch), '  ',
            truncated_field(fields[:text], widths.snippet), '  ',
            truncated_field(fields[:note], widths.note)
          ]
        end

        def truncated_field(text, width)
          pad_right(truncate_text(text, width), width)
        end

        def append_optional_columns(parts, annotation, fields, widths)
          parts.push('  ', build_book_cell(annotation, widths.book)) if widths.book_col?
          parts.push('  ', truncated_field(fields[:date], widths.date))
        end

        def extract_row_fields(annotation)
          {
            text: (annotation[:text] || 'No text').to_s.tr("\n", ' '),
            note: (annotation[:note] || '').to_s.tr("\n", ' '),
            date: (annotation[:created_at] || '').to_s.split('T').first,
            chapter: format_chapter(annotation[:chapter_index]),
          }
        end

        def format_chapter(chapter_index)
          (chapter_index.nil? ? '-' : chapter_index.to_i).to_s
        end

        def build_book_cell(annotation, width)
          bp = annotation[:book_path]
          book = bp ? sanitize_filename(File.basename(bp)) : ''
          pad_right(truncate_text(book, width), width)
        end

        def sanitize_filename(raw)
          Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(
            raw, preserve_newlines: false, preserve_tabs: false
          )
        end
      end

      # Normalized view of annotation data for screen rendering.
      class AnnotationView
        def initialize(annotation)
          @annotation = annotation.is_a?(Hash) ? annotation : {}
        end

        def text
          fetch(:text).to_s
        end

        def note
          fetch(:note).to_s
        end

        def chapter_index
          fetch(:chapter_index)
        end

        def id
          fetch(:id)
        end

        def formatted_date
          created = fetch(:created_at)
          created.to_s.tr('T', ' ').sub('Z', '')
        end

        def page_meta
          curr = fetch(:page_current)
          total = fetch(:page_total)
          return nil unless curr && total

          mode = fetch(:page_mode).to_s
          label = mode.empty? ? '' : "#{mode}: "
          "#{label}#{curr}/#{total}"
        end

        private

        def fetch(key)
          @annotation[key] || @annotation[key.to_s]
        end
      end

      # Text box helper for annotation screens.
      class AnnotationTextBox
        BOX_COLUMN = 2
        TEXT_COLUMN = 4
        BOX_SPACING = 2
        MIN_HEIGHT = 6
        BOTTOM_PADDING = 3

        attr_reader :row, :height, :width, :label, :text, :style

        def initialize(row:, height:, width:, label:, text:, style: :plain)
          @row = row
          @height = height
          @width = width
          @label = label
          @text = text.to_s
          @style = style
        end

        def inner_width
          width - 4
        end

        def frame_args
          {
            row: row,
            height: height,
            width: width,
            label: label,
          }
        end

        def each_visible_line(&block)
          return enum_for(__method__) unless block

          lines = if style == :markup
                    UI::AnnotationMarkup::Styler.new(text).render_lines(inner_width)
                  else
                    UI::TextUtils.wrap_text(text, inner_width)
                  end

          lines.first(max_lines).each_with_index(&block)
        end

        def render(context, drawer:, color_prefix:)
          drawer.draw_box(
            context.surface,
            context.bounds,
            row,
            BOX_COLUMN,
            height,
            width,
            label: label
          )
          render_lines(context, color_prefix: color_prefix)
        end

        def render_lines(context, color_prefix:)
          line_reset = UI::AnnotationMarkup::STYLE_RESET

          each_visible_line do |line, index|
            display = style == :markup ? (line + line_reset) : line
            padded = UI::TextUtils.pad_right(display, inner_width)
            context.surface.write(
              context.bounds,
              row + 1 + index,
              TEXT_COLUMN,
              "#{color_prefix}#{padded}#{context.reset}"
            )
          end
        end

        def cursor_position(cursor)
          if style == :markup
            renderer = UI::AnnotationMarkup::Styler.new(text)
            line_idx, col = renderer.cursor_position(cursor, inner_width)
            cursor_row = row + 1 + line_idx
            cursor_col = TEXT_COLUMN + col
            return [cursor_row, cursor_col]
          end

          cursor_lines = UI::TextUtils.wrap_text(text[0, cursor], inner_width)
          cursor_row = row + 1 + [cursor_lines.length - 1, 0].max
          last_line = cursor_lines.last || ''
          cursor_col = TEXT_COLUMN + Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(last_line)
          [cursor_row, cursor_col]
        end

        def next_box(total_height:, label:, text:, style: nil)
          next_row = row + height + BOX_SPACING
          next_height = [total_height - next_row - BOTTOM_PADDING, MIN_HEIGHT].max
          AnnotationTextBox.new(
            row: next_row,
            height: next_height,
            width: width,
            label: label,
            text: text,
            style: style || @style
          )
        end

        private

        def max_lines
          [height - 2, 0].max
        end
      end

      # Menu-state helper for annotation edit screens.
      class AnnotationEditState
        def initialize(dependencies = nil)
          @dependencies = dependencies
          @menu_state_reader = nil
          @menu_state_writer = nil
        end

        def text
          (menu_state_reader&.annotation_edit_text || '').to_s
        end

        def cursor(text = self.text)
          (menu_state_reader&.annotation_edit_cursor || text.length).to_i
        end

        def update_from
          current_text = text
          current_cursor = cursor(current_text)
          updated = yield(current_text, current_cursor)
          update(text: updated[0], cursor: updated[1]) if updated
        end

        def update(text:, cursor:)
          menu_state_writer&.update_annotation_edit(text: text, cursor: cursor)
        end

        def selected_annotation
          ann = menu_state_reader&.selected_annotation
          ann if ann.is_a?(Hash)
        end

        def annotation_update_payload
          annotation = selected_annotation || {}
          path = menu_state_reader&.selected_annotation_book
          ann_id = annotation[:id] || annotation['id']
          return nil unless path && ann_id

          { path: path, ann_id: ann_id, text: text }
        end

        def refresh_annotations(service)
          menu_state_writer&.update_annotations_all(service.list_all)
        end

        def return_to_annotations_list
          menu_state_writer&.update_mode(:annotations)
        end

        private

        def menu_state_reader
          @menu_state_reader ||= @dependencies&.menu_state_reader
        end

        def menu_state_writer
          @menu_state_writer ||= @dependencies&.menu_state_writer
        end
      end
    end
  end
end
