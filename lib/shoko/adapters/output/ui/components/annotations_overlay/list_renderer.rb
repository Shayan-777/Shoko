# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative '../../../terminal/text_metrics'
require_relative '../../../terminal/terminal'

module Shoko
  module Adapters::Output::Ui::Components
    # Namespace for annotations overlay helpers.
    module AnnotationsOverlay
      # Renders the annotations list and header within the overlay.
      class ListRenderer
        include Adapters::Output::Ui::Constants::Ui

        # Rendering inputs for the annotations overlay list.
        RenderContext = Struct.new(:surface, :bounds, :layout, :items, :selected_index, keyword_init: true)

        ColumnWidths = Struct.new(:idx, :snippet, :note, :date, keyword_init: true)

        def render(context)
          draw_title(context)
          draw_entries(context)
        end

        private

        def draw_title(context)
          surface = context.surface
          bounds = context.bounds
          layout = context.layout
          count = context.items.length
          origin_x = layout.origin_x
          reset = Terminal::ANSI::RESET
          title = "#{COLOR_TEXT_ACCENT}📝 Annotations (#{count})#{reset}"
          title_row = layout.origin_y + 1
          title_col = origin_x + 2
          surface.write(bounds, title_row, title_col, title)

          info_plain = '[Enter] Open • [e] Edit • [d] Delete • [Esc] Close'
          info_col = origin_x + [
            layout.width - Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(info_plain) - 2, 2
          ].max
          surface.write(bounds, title_row, info_col, "#{COLOR_TEXT_DIM}#{info_plain}#{reset}")
        end

        def draw_entries(context)
          layout = context.layout
          entries = context.items
          list_top = layout.origin_y + 3
          list_height = [layout.height - 5, 1].max
          inner_width = layout.width - 4

          if entries.empty?
            render_empty(context)
            return
          end

          columns = build_columns(inner_width)
          render_header(context, columns, list_top)
          render_rows(context, columns, list_top, list_height)
        end

        def render_empty(context)
          surface = context.surface
          bounds = context.bounds
          layout = context.layout
          message = "#{COLOR_TEXT_DIM}No annotations yet#{Terminal::ANSI::RESET}"
          row = layout.origin_y + (layout.height / 2)
          col = layout.origin_x + [(layout.width - Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(message)) / 2,
                                   2].max
          surface.write(bounds, row, col, message)
        end

        def build_columns(inner_width)
          idx_width = 4
          date_width = [12, inner_width / 5].max
          remaining = inner_width - idx_width - date_width - 2
          remaining = 12 if remaining < 12
          snippet_width = [(remaining * 0.6).floor, 8].max
          note_width = [remaining - snippet_width, 6].max
          ColumnWidths.new(idx: idx_width, snippet: snippet_width, note: note_width, date: date_width)
        end

        def render_header(context, columns, list_top)
          surface = context.surface
          bounds = context.bounds
          layout = context.layout
          header = [
            '  ',
            Ui::TextUtils.pad_right('#', columns.idx),
            ' ',
            Ui::TextUtils.pad_right('Snippet', columns.snippet),
            ' ',
            Ui::TextUtils.pad_right('Note', columns.note),
            ' ',
            Ui::TextUtils.pad_right('Saved', columns.date),
          ].join
          surface.write(bounds, list_top - 1, layout.origin_x + 2,
                        "#{COLOR_TEXT_DIM}#{header}#{Terminal::ANSI::RESET}")
        end

        def render_rows(context, columns, list_top, list_height)
          surface = context.surface
          bounds = context.bounds
          layout = context.layout
          selected_index = context.selected_index
          entries = context.items
          start_index, visible = Ui::ListHelpers.slice_visible(entries, list_height, selected_index)
          list_col = layout.origin_x + 2

          visible.each_with_index do |annotation, offset|
            entry_index = start_index + offset
            is_selected = entry_index == selected_index
            line_color = is_selected ? SELECTION_HIGHLIGHT : COLOR_TEXT_PRIMARY
            pointer = is_selected ? '▸' : ' '

            line = build_line(annotation, entry_index, columns, pointer)
            surface.write(bounds, list_top + offset, list_col, "#{line_color}#{line}#{Terminal::ANSI::RESET}")
          end
        end

        def build_line(annotation, entry_index, columns, pointer)
          snippet = format_cell(annotation[:text], columns.snippet)
          note = format_cell(annotation[:note], columns.note)
          saved = format_cell(saved_text(annotation), columns.date)
          idx_text = Ui::TextUtils.pad_right((entry_index + 1).to_s, columns.idx)

          [pointer, ' ', idx_text, ' ', snippet, ' ', note, ' ', saved].join
        end

        def format_cell(value, width)
          text = value.to_s.tr("\n", ' ')
          Ui::TextUtils.pad_right(Ui::TextUtils.truncate_text(text, width), width)
        end

        def saved_text(annotation)
          saved_at = annotation[:updated_at] || annotation[:created_at]
          saved_at ? saved_at.to_s.split('T').first : '-'
        end
      end
    end
  end
end
