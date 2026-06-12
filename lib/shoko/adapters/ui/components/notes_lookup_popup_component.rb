# frozen_string_literal: true

require_relative 'base_component'
require_relative 'bottom_left_panel'
require_relative 'ui/cursor_blink'
require_relative 'ui/note_markup'
require_relative '../../../shared/terminal/text_metrics'
require_relative 'status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        # The reader "Annotation Notes" panel: a left-anchored card docked directly
        # onto the bottom status bar (which becomes a quiet toolbar) that snaps flush
        # to the left edge and grows upward. The fifth member of the bar-anchored
        # family, alongside the in-book search list, the dictionary card, the TOC
        # panel, and the translator workspace — same elevated slate surface, with a
        # soft-rose ✎ as its signature accent and a brand-blue selection pointer.
        #
        # Two faces, switched by `notes_composing` in state:
        #   * list face — the book's notes as roomy three-row blocks (the note, the
        #     highlighted excerpt it annotates, and its location); ↑/↓ move the
        #     selection, ↵ jumps, e edits, n adds, d deletes; and
        #   * compose face — a context line (the excerpt, or a "new note" hint) over a
        #     multi-line note editor well with the same blinking thin-stripe caret the
        #     translator/annotation editors use.
        #
        # Like the rest of the family it is an overlay, not a split panel: on a wide
        # screen the centered text leaves an empty left margin and the card tucks into
        # it and grows taller; when the text fills the width it keeps its natural width
        # and overlaps the bottom of the page — the prose never recomposes. A pure
        # renderer: it owns no selection/draft/caret state and re-renders from the
        # reader view-state store each frame.
        class NotesLookupPopupComponent < BaseComponent
          include BottomLeftPanel
          include Ui::CursorBlink

          Palette = StatusBar::Palette

          MAX_ROWS = 15      # row ceiling when the panel keeps its natural width
          MAX_ROWS_TALL = 27 # taller ceiling when it shrinks into the left margin
          MAX_WIDTH = 72
          MIN_WIDTH = 30
          ROWS_PER_NOTE = 3  # text row + excerpt row + location row per note block
          MAX_NOTES = 4      # block ceiling when the panel keeps its natural width
          MAX_NOTES_TALL = 8 # taller ceiling when it shrinks into the left margin
          MIN_EDITOR_ROWS = 6 # the compose well always reads as a roomy multi-line field
          SCROLLBAR_WIDTH = 1
          PAD = 2            # left margin for text content
          RIGHT_GAP = 1      # blank column kept to the right of the text
          SELECTED_STRIPE = '▋ ' # selection bar down the active entry's left edge (matches search)
          BLANK_MARK = '  ' # blank lead of the same width for inactive entries
          CONTENT_LEFT = 2 # columns before the body text (just the lead bar / blank)
          SCROLL_GLYPH = '█'

          DIM = "\e[2m"
          ITALIC = "\e[3m"
          STYLE_RESET = "\e[22;23;24m"

          attr_reader :notes, :selected_index, :scroll_offset, :composing, :cursor

          def initialize(reader_state_reader:, color_mode: :dark)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = color_mode
            @notes = []
            @selected_index = 0
            @scroll_offset = 0
            @visible_notes = 1
            @composing = false
            @draft = ''
            @cursor = 0
            @editing_id = nil
            @editing_text = ''
            @editing_chapter = nil
            @cursor_signature = nil
            initialize_cursor_blink
          end

          def visible?
            @reader_state_reader&.mode == :notes
          end

          # Theme-independent (fixed slate palette, like the bar); kept for parity
          # with the session's refresh_theme call.
          def update_color_mode(mode)
            @color_mode = mode
          end

          def do_render(surface, bounds)
            return unless visible?

            sync_from_state
            @composing ? render_compose(surface, bounds) : render_list(surface, bounds)
          end

          private

          def sync_from_state
            reader = @reader_state_reader
            @composing = reader&.notes_composing == true
            @notes = normalize_notes(reader&.annotations)
            @selected_index = (reader&.notes_selected_index || 0).to_i
            @draft = (reader&.notes_draft || '').to_s
            @cursor = (reader&.notes_cursor || 0).to_i.clamp(0, @draft.length)
            @editing_id = reader&.notes_editing_id
            @editing_text = (reader&.notes_editing_text || '').to_s
            @editing_chapter = reader&.notes_editing_chapter
            clamp_selection!
            note_cursor_activity if @composing
          end

          # Hold the caret solid for a beat whenever the draft or caret moves, then let
          # CursorBlink resume blinking once idle — matching the translator editor.
          def note_cursor_activity
            signature = [@draft, @cursor]
            record_cursor_activity if signature != @cursor_signature
            @cursor_signature = signature
          end

          # ===== list face =====

          def render_list(surface, bounds, _layout = nil)
            return render_empty(surface, bounds) if @notes.empty?

            layout = list_layout(bounds)
            return unless layout

            ensure_selection_visible!(layout[:visible])
            render_list_rule(surface, bounds, layout)
            render_scrollbar(surface, bounds, layout) if layout[:scrollbar]
            layout[:visible].times { |slot| render_note_block(surface, bounds, layout, slot) }
          end

          def list_layout(bounds)
            bottom_row = bounds.height - 1
            available = bottom_row - 1 # rows for the top rule plus the note blocks
            return nil if bounds.width < MIN_WIDTH || available < ROWS_PER_NOTE

            width, constrained = fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH)
            @visible_notes = visible_note_count(constrained, available)
            clamp_scroll!
            content_rows = @visible_notes * ROWS_PER_NOTE
            {
              col: 1, width: width, bottom_row: bottom_row, visible: @visible_notes,
              content_rows: content_rows, rule_row: bottom_row - content_rows,
              scrollbar: @notes.length > @visible_notes
            }
          end

          def visible_note_count(constrained, available)
            cap = row_ceiling(constrained, MAX_NOTES, MAX_NOTES_TALL)
            [[@notes.length, cap, available / ROWS_PER_NOTE].min, 1].max
          end

          # Top hairline rule: "── Notes ········· 3 notes ──".
          def render_list_rule(surface, bounds, layout)
            row = layout[:rule_row]
            return if row < 1

            left = @scroll_offset.positive? ? "↑ #{@scroll_offset} more" : 'Notes'
            surface.write(bounds, row, layout[:col], rule_text(left, count_label, layout[:width]))
          end

          def count_label
            count = @notes.length
            "#{count} #{count == 1 ? 'note' : 'notes'}"
          end

          def render_note_block(surface, bounds, layout, slot)
            absolute = @scroll_offset + slot
            note = @notes[absolute]
            return unless note

            selected = absolute == @selected_index
            reserve = layout[:scrollbar] ? SCROLLBAR_WIDTH : 0
            width = layout[:width] - reserve
            top = layout[:rule_row] + 1 + (slot * ROWS_PER_NOTE)
            note_block_rows(note, width, selected).each_with_index do |row, offset|
              surface.write(bounds, top + offset, layout[:col], row)
            end
          end

          # A roomy three-row block, mirroring the in-book search result: the active
          # entry carries a brand-blue bar down its whole left edge (the rest are
          # blank-indented so text lines up), then the note, the highlighted excerpt
          # it annotates (or a page-note marker), and its location.
          def note_block_rows(note, width, selected)
            background = selected ? Palette::NOTES_SELECTED_BG : Palette::NOTES_BG
            lead = row_lead(selected, background)
            [
              note_line(note, lead, width, background),
              excerpt_line(note, lead, width, background),
              location_line(note, lead, width, background),
            ]
          end

          # The shared left edge: the selection bar on the active entry, otherwise a
          # blank of the same width so every entry's text aligns at the same column.
          def row_lead(selected, background)
            return cell(SELECTED_STRIPE, Palette::NOTES_POINTER_FG, background) if selected

            cell(BLANK_MARK, Palette::NOTES_DIM_FG, background)
          end

          def note_line(note, lead, width, background)
            body, fg = note_body(note[:note].strip)
            "#{lead}#{filled(body, fg, background, width - CONTENT_LEFT)}#{Palette::RESET}"
          end

          # [styled body, foreground]: a dim placeholder for an empty note, otherwise
          # the note text with inline markup (markers kept visible but quiet).
          def note_body(raw)
            return ['(empty note)', Palette::NOTES_DIM_FG] if raw.empty?

            [markup(raw.tr("\n", ' '), Palette::NOTES_NOTE_FG), Palette::NOTES_NOTE_FG]
          end

          # Inline markup styling (bold/underline/strike/italic/lists) that keeps the
          # marker glyphs visible but quiet, so display width == raw width.
          def markup(text, base_fg)
            Ui::NoteMarkup.style_line(text, base_fg: base_fg, marker_fg: Palette::NOTES_MARKUP_FG)
          end

          # The quote the note annotates, italicised — or a quiet marker for a
          # page/chapter-level note that isn't tied to a specific quote.
          def excerpt_line(note, lead, width, background)
            excerpt = note[:text].strip.tr("\n", ' ')
            body = excerpt.empty? ? '— note on this page —' : "“#{excerpt}”"
            italic_fg = "#{ITALIC}#{Palette::NOTES_EXCERPT_FG}"
            "#{lead}#{filled(body, italic_fg, background, width - CONTENT_LEFT)}#{Palette::RESET}"
          end

          def location_line(note, lead, width, background)
            "#{lead}#{filled(location_label(note), Palette::NOTES_DIM_FG, background, width - CONTENT_LEFT)}" \
              "#{Palette::RESET}"
          end

          def location_label(note)
            title = note[:chapter_title].strip
            parts = [title.empty? ? "Chapter #{note[:chapter_index].to_i + 1}" : title]
            parts << "Page #{note[:page]}" if note[:page]
            parts.join(' · ')
          end

          # Truncate body to the room (minus the right gap) and pad it back out so the
          # row's background fills the whole panel width.
          def filled(text, foreground, background, room)
            text_room = [room - RIGHT_GAP, 1].max
            shown = truncate(text, text_room)
            pad = [text_room - visible_length(shown), 0].max + RIGHT_GAP
            "#{cell(shown, foreground, background)}#{cell(' ' * pad, foreground, background)}"
          end

          def render_empty(surface, bounds)
            width, = fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH)
            bottom_row = bounds.height - 1
            return if bottom_row < 4

            lines = [
              seg(' Notes', "#{Palette::BOLD}#{Palette::NOTES_NOTE_FG}"),
              dim_line(' No notes yet.'),
              dim_line(' Highlight text while reading,'),
              dim_line(' then choose Annotate to add one.'),
            ]
            rule_row = bottom_row - lines.length
            surface.write(bounds, rule_row, 1, rule_text('Notes', '0 notes', width)) if rule_row >= 1
            lines.each_with_index do |line, offset|
              row = rule_row + 1 + offset
              surface.write(bounds, row, 1, body_line(line, width)) if row.between?(1, bottom_row)
            end
          end

          # ===== compose face =====

          def render_compose(surface, bounds)
            width = card_width(bounds)
            text_width = [width - PAD - RIGHT_GAP, 8].max
            rows = wrap_indices(@draft, text_width)
            layout = compose_layout(bounds, width, rows.length)
            return unless layout

            render_rule(surface, bounds, layout[:rule_row], width, compose_title_spans, compose_meta)
            surface.write(bounds, layout[:rule_row] + 1, layout[:col], body_line(compose_header(text_width), width))
            render_editor(surface, bounds, layout, width, text_width, rows)
          end

          # Anchored at the bar and grown upward: rule · context line · editor well.
          def compose_layout(bounds, width, source_count)
            bottom_row = bounds.height - 1
            return nil if bounds.width < MIN_WIDTH || bottom_row < 5

            _, constrained = fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH)
            max_total = [constrained ? MAX_ROWS_TALL : MAX_ROWS, bottom_row].min
            source_need = [source_count, MIN_EDITOR_ROWS].max
            total = [2 + source_need, max_total].min
            source_rows = [total - 2, 1].max
            rule_row = bottom_row - total + 1
            return nil if rule_row < 1

            { col: 1, width: width, bottom_row: bottom_row, rule_row: rule_row, source_rows: source_rows }
          end

          def render_editor(surface, bounds, layout, width, text_width, rows)
            cursor_row, cursor_col = cursor_location(rows)
            top = scroll_to_cursor(rows.length, layout[:source_rows], cursor_row)
            layout[:source_rows].times do |slot|
              idx = top + slot
              line = editor_line(rows[idx], text_width, idx == cursor_row ? cursor_col : nil, slot)
              surface.write(bounds, layout[:rule_row] + 2 + slot, layout[:col], padded_field(line, width))
            end
          end

          def editor_line(row, text_width, caret_col, slot)
            return field_seg(placeholder_text(text_width), Palette::NOTES_PLACEHOLDER_FG) if @draft.empty? && slot.zero?
            return field_seg('', Palette::NOTES_INPUT_FG) if row.nil?

            text_with_caret(row[:text].to_s, text_width, caret_col)
          end

          def text_with_caret(text, text_width, caret_col)
            styled = "#{Palette::RESET}#{Palette::NOTES_FIELD_BG}#{Palette::NOTES_INPUT_FG}" \
                     "#{markup(text, Palette::NOTES_INPUT_FG)}"
            return truncate(styled, text_width) if caret_col.nil?

            inline_cursor_text(
              styled, caret_col, width: text_width,
                                 style_prefix: "#{Palette::NOTES_FIELD_BG}#{Palette::NOTES_CARET_FG}",
                                 restore_prefix: "#{Palette::NOTES_FIELD_BG}#{Palette::NOTES_INPUT_FG}"
            )
          end

          def placeholder_text(text_width)
            truncate('Write your note…', text_width)
          end

          def padded_field(line, width)
            pad = [width - PAD - visible_length(line), 0].max
            "#{field_seg(' ' * PAD, Palette::NOTES_INPUT_FG)}#{line}" \
              "#{field_seg(' ' * pad, Palette::NOTES_INPUT_FG)}#{Palette::RESET}"
          end

          def compose_header(text_width)
            excerpt = @editing_text.to_s.strip.gsub(/\s+/, ' ')
            return quote_text(truncate("“#{excerpt}”", text_width)) unless excerpt.empty?

            dim_line(truncate(@editing_id ? 'Editing this note' : "New note · #{compose_location}", text_width))
          end

          def compose_location
            "Chapter #{@editing_chapter.to_i + 1}"
          end

          def compose_title_spans
            label = @editing_id ? 'Edit note' : 'New note'
            styled = seg(label, "#{Palette::BOLD}#{Palette::NOTES_ACCENT_FG}")
            [styled, visible_length(label)]
          end

          def compose_meta
            label = '↵ save · Esc back'
            [seg(label, Palette::NOTES_DIM_FG), visible_length(label)]
          end

          # ===== shared geometry + drawing =====

          def card_width(bounds)
            fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH).first
          end

          # Top hairline rule: "── <left> ········· <right> ──".
          def rule_text(left, right, width)
            rule_fg = Palette::NOTES_RULE_FG
            head = truncate(left, [width - 16, 4].max)
            dots = '·' * [width - visible_length(head) - visible_length(right) - 8, 1].max

            "#{seg('── ', rule_fg)}#{seg(head, Palette::NOTES_DIM_FG)}#{seg(" #{dots} ", rule_fg)}" \
              "#{seg(right, Palette::NOTES_DIM_FG)}#{seg(' ──', rule_fg)}#{Palette::RESET}"
          end

          # Rule built from pre-styled [span, visible_length] pairs (compose face).
          def render_rule(surface, bounds, row, width, left, right)
            return if row < 1

            left_span, left_len = left
            right_span, right_len = right
            rule_fg = Palette::NOTES_RULE_FG
            fill = [width - left_len - right_len - 8, 1].max
            text = "#{seg('── ', rule_fg)}#{left_span}#{seg(" #{'·' * fill} ", rule_fg)}" \
                   "#{right_span}#{seg(' ──', rule_fg)}#{Palette::RESET}"
            surface.write(bounds, row, 1, text)
          end

          # A body line over the panel background: a left margin, the (already-styled)
          # line, padded out to the width.
          def body_line(text, width)
            base = "#{Palette::RESET}#{Palette::NOTES_BG}#{Palette::NOTES_NOTE_FG}"
            safe = text.to_s.gsub(Palette::RESET, base)
            pad = [width - PAD - visible_length(safe), 0].max
            "#{base}#{' ' * PAD}#{safe}#{' ' * pad}#{Palette::RESET}"
          end

          def render_scrollbar(surface, bounds, layout)
            rows = layout[:content_rows]
            thumb = scrollbar_thumb(rows, layout[:visible])
            top = layout[:rule_row] + 1
            col = layout[:col] + layout[:width] - 1
            rows.times do |offset|
              in_thumb = offset >= thumb[:start] && offset < thumb[:start] + thumb[:size]
              color = in_thumb ? Palette::NOTES_SCROLL_THUMB_FG : Palette::NOTES_SCROLL_TRACK_FG
              surface.write(bounds, top + offset, col, "#{Palette::RESET}#{Palette::NOTES_BG}#{color}#{SCROLL_GLYPH}")
            end
          end

          def scrollbar_thumb(rows, visible)
            total = [@notes.length, 1].max
            size = (visible.to_f / total * rows).round.clamp(1, rows)
            room = rows - size
            denom = [total - visible, 1].max
            start = room <= 0 ? 0 : ((@scroll_offset.to_f / denom) * room).round.clamp(0, room)
            { size: size, start: start }
          end

          def ensure_selection_visible!(visible)
            if @selected_index < @scroll_offset
              @scroll_offset = @selected_index
            elsif @selected_index >= @scroll_offset + visible
              @scroll_offset = @selected_index - visible + 1
            end
            clamp_scroll!
          end

          def clamp_selection!
            @selected_index = @notes.empty? ? 0 : @selected_index.clamp(0, @notes.length - 1)
          end

          def clamp_scroll!
            max = [@notes.length - [@visible_notes, 1].max, 0].max
            @scroll_offset = @scroll_offset.clamp(0, max)
          end

          def normalize_notes(raw)
            Array(raw).filter_map do |ann|
              next unless ann.is_a?(Hash)

              {
                note: value(ann, :note).to_s,
                text: value(ann, :text).to_s,
                chapter_index: value(ann, :chapter_index).to_i,
                chapter_title: value(ann, :chapter_title).to_s,
                page: page_value(ann),
              }
            end
          end

          # The note's page under the CURRENT pagination, recomputed live by the
          # controller (`display_page`) from the stored reading position, so it stays
          # correct across terminal resizes. Nil when not yet computed / unknown.
          def page_value(entry)
            page = value(entry, :display_page)
            return nil if page.nil? || page.to_s.strip.empty?

            page.to_i
          end

          def value(entry, key)
            return entry[key] if entry.key?(key)

            entry[key.to_s]
          end

          # ----- caret/wrap helpers (shared shape with the translator editor) -----

          # Map the flat caret index onto a (row, column) in the wrapped layout.
          def cursor_location(rows)
            rows.each_with_index do |row, index|
              finish = row[:start] + row[:text].length
              next unless @cursor.between?(row[:start], finish)
              next if crosses_into_next?(rows, index)

              return [index, @cursor - row[:start]]
            end
            last = rows.length - 1
            [last, rows[last][:text].length]
          end

          def crosses_into_next?(rows, index)
            nxt = rows[index + 1]
            return false unless nxt

            @cursor == nxt[:start] && @cursor != rows[index][:start]
          end

          def scroll_to_cursor(total, visible, cursor_row)
            return 0 if total <= visible

            (cursor_row - visible + 1).clamp(0, total - visible)
          end

          # Word-wrap that honors hard newlines and preserves every character,
          # recording each row's start index so the flat caret maps onto (row, column).
          def wrap_indices(text, width)
            width = [width.to_i, 1].max
            rows = []
            index = 0
            length = text.length
            loop do
              newline = text.index("\n", index)
              line_end = newline || length
              wrap_segment(rows, text, index, line_end, width)
              break unless newline

              index = newline + 1
            end
            rows
          end

          def wrap_segment(rows, text, start, line_end, width)
            if start == line_end
              rows << { text: '', start: start }
              return line_end
            end

            index = start
            index = append_wrapped_row(rows, text, index, width, line_end) while index < line_end
            line_end
          end

          def append_wrapped_row(rows, text, cursor, width, line_end)
            remaining = line_end - cursor
            if remaining <= width
              rows << { text: text[cursor...line_end], start: cursor }
              return line_end
            end

            window = text[cursor, width]
            brk = window.rindex(' ')
            take = brk&.positive? ? brk + 1 : width
            rows << { text: text[cursor, take], start: cursor }
            cursor + take
          end

          # Plain word-wrap (no index tracking); honors hard newlines.
          def wrap(text, width)
            width = [width.to_i, 1].max
            text.to_s.split("\n").flat_map { |paragraph| wrap_paragraph(paragraph, width) }
          end

          def wrap_paragraph(paragraph, width)
            words = paragraph.strip.split(/\s+/)
            return [''] if words.empty?

            words.each_with_object([]) do |word, lines|
              if lines.empty? || visible_length("#{lines.last} #{word}") > width
                lines << word
              else
                lines[-1] = "#{lines.last} #{word}"
              end
            end
          end

          # ----- styled spans -----

          def seg(text, foreground)
            "#{Palette::RESET}#{Palette::NOTES_BG}#{foreground}#{text}"
          end

          def field_seg(text, foreground)
            "#{Palette::RESET}#{Palette::NOTES_FIELD_BG}#{foreground}#{text}"
          end

          def cell(text, foreground, background)
            "#{Palette::RESET}#{background}#{foreground}#{text}"
          end

          def dim_line(text)
            "#{DIM}#{Palette::NOTES_DIM_FG}#{text}#{STYLE_RESET}"
          end

          def quote_text(text)
            "#{ITALIC}#{Palette::NOTES_EXCERPT_FG}#{text}#{STYLE_RESET}"
          end

          def visible_length(text)
            Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
          end

          def truncate(text, width)
            Shoko::Shared::Terminal::TextMetrics.truncate_to(text.to_s, [width.to_i, 0].max)
          end
        end
      end
    end
  end
end
