# frozen_string_literal: true

require_relative 'base_component'
require_relative 'bottom_left_panel'
require_relative 'overlay_mouse_target'
require_relative 'ui/cursor_blink'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/language_directory'
require_relative 'status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        # The reader "Translator workspace": a left-anchored card docked directly onto
        # the bottom status bar — the same place the dictionary card lives — that
        # snaps flush to the left edge and grows upward. Unlike its lookup cousins
        # (whose single-line query rides the status bar), the translator keeps its
        # source text *inside* the card as a roomy multi-line editor well, so you can
        # compose more than a sentence and watch it wrap; the translation flows below
        # a labeled divider. Its signature is a soft emerald source→target arrow.
        #
        # Two faces, switched by `translator_picker_side` in state:
        #   * editor mode — the headword rule carries the language pair; below it a
        #     source well (bright text, a block caret that the view auto-scrolls to
        #     keep visible) sits over a "↓ <target language>" divider and the wrapped
        #     translation; and
        #   * language-picker mode — the card becomes a filterable, selectable list of
        #     languages for the active side, with the live pair on the rule.
        #
        # Like the rest of the family it is an overlay, not a split panel: on a wide
        # screen the centered text leaves an empty left margin and the card tucks into
        # it and grows taller; when the text fills the width it keeps its natural width
        # and overlaps the bottom of the page — the prose never recomposes. A pure
        # renderer: it owns no source/result/caret state and re-renders from the reader
        # view-state store each frame.
        class TranslatorLookupPopupComponent < BaseComponent
          include BottomLeftPanel
          include OverlayMouseTarget
          include Ui::CursorBlink

          Palette = StatusBar::Palette
          LanguageDirectory = Shoko::Shared::LanguageDirectory

          MAX_ROWS = 22      # card-height ceiling when it keeps its natural width
          MAX_ROWS_TALL = 32 # taller ceiling when it shrinks into the left margin
          MAX_WIDTH = 76
          MIN_WIDTH = 32
          MIN_SOURCE_ROWS = 6 # the source well always reads as a roomy multi-line field
          MIN_TARGET_ROWS = 4
          SCROLLBAR_WIDTH = 1
          PAD = 2            # left margin for text content inside each region
          RIGHT_GAP = 2      # right margin kept clear of the panel edge
          CODE_WIDTH = 5     # fixed gutter for the language code in the picker list
          POINTER = '▸ '
          CURRENT_MARK = '● '
          BLANK_MARK = '  '
          ARROW = '→'
          SCROLL_GLYPH = '█'
          SOURCE_LABEL = 'Source'
          TARGET_LABEL = 'Target'
          # Filled, fixed-width action buttons. The width holds the longest label
          # ("Pasted!"/"Copied!") so it never changes as the label flips.
          PASTE_LABEL = 'Paste'
          PASTED_LABEL = 'Pasted!'
          COPY_LABEL = 'Copy'
          COPIED_LABEL = 'Copied!'
          BUTTON_TEXT_WIDTH = 7 # the widest label
          BUTTON_WIDTH = BUTTON_TEXT_WIDTH + 2 # plus one padding space each side
          CLOSE_GLYPH = '✕'
          CLOSE_WIDTH = 3 # the red "✕" close box: the glyph plus a padding space each side

          DIM = "\e[2m"
          STYLE_RESET = "\e[22;23;24m"

          attr_reader :source_lang, :target_lang, :picker_side, :picker_index, :cursor

          def initialize(reader_state_reader:, color_mode: :dark)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = color_mode
            @result = nil
            @query = ''
            @results_query = ''
            @source_lang = LanguageDirectory::AUTO
            @target_lang = 'en'
            @languages = []
            @picker_side = nil
            @picker_query = ''
            @picker_index = 0
            @scroll = 0
            @cursor = 0
            @picker_scroll = 0
            @cursor_signature = nil
            initialize_cursor_blink
          end

          def visible?
            @reader_state_reader&.mode == :translator
          end

          def update_color_mode(mode)
            @color_mode = mode
          end

          def do_render(surface, bounds)
            clear_overlay_geometry
            @lang_regions = nil
            @paste_region = nil
            @copy_region = nil
            @close_region = nil
            return unless visible?

            sync_from_state
            @picker_side ? render_picker(surface, bounds) : render_editor(surface, bounds)
          end

          # Click targets, checked before the shared list/dismiss hit-testing: the
          # Paste/Copy buttons, then the source/target labels (which open the picker,
          # or flip its side from inside it).
          def hit_test(column, row)
            action_region(column, row) || language_region(column, row) || super
          end

          private

          def sync_from_state
            reader = @reader_state_reader
            @result = reader&.translator_result
            @query = (reader&.translator_query || '').to_s
            @results_query = (reader&.translator_results_query || '').to_s
            @source_lang = (reader&.translator_source_lang || LanguageDirectory::AUTO).to_s
            @target_lang = (reader&.translator_target_lang || 'en').to_s
            @languages = Array(reader&.translator_languages)
            @picker_side = normalize_side(reader&.translator_picker_side)
            @picker_query = (reader&.translator_picker_query || '').to_s
            @picker_index = (reader&.translator_picker_index || 0).to_i
            @hover_index = reader&.overlay_hover_index
            @feedback = normalize_feedback(reader&.translator_feedback)
            @scroll = (reader&.translator_scroll || 0).to_i
            @cursor = (reader&.translator_cursor || 0).to_i.clamp(0, @query.length)
            note_cursor_activity
          end

          # Hold the caret solid for a beat whenever the text or caret moves (typing,
          # navigating), then let CursorBlink resume blinking once idle — matching the
          # annotation editor.
          def note_cursor_activity
            signature = [@query, @cursor, @picker_side]
            record_cursor_activity if signature != @cursor_signature
            @cursor_signature = signature
          end

          def normalize_side(side)
            return :source if side.to_s == 'source'
            return :target if side.to_s == 'target'

            nil
          end

          # ----- editor mode -----

          def render_editor(surface, bounds)
            width = card_width(bounds)
            text_width = [width - PAD - RIGHT_GAP, 8].max
            source_rows = wrap_indices(@query, text_width)
            target_lines = target_display_lines(text_width)
            layout = editor_layout(bounds, width, source_rows.length, target_lines.length)
            return unless layout

            record_editor_hit_regions(layout, width)
            render_rule(surface, bounds, layout[:rule_row], width, pair_spans, editor_meta, right_cap: '')
            render_source(surface, bounds, layout, width, text_width, source_rows)
            render_divider(surface, bounds, layout[:divider_row], width)
            render_target(surface, bounds, layout, width, target_lines)
          end

          # The editor face has no clickable rows; record it (count 0) so it is inert
          # to row clicks. The language labels, the Paste button, and the red close
          # box are the click targets (the Copy button is recorded by the divider,
          # since it only exists once there is output).
          def record_editor_hit_regions(layout, width)
            record_overlay_geometry(
              rule_row: layout[:rule_row], col: layout[:col], width: width,
              visible: 0, rows_per: 1, scroll: 0, count: 0
            )
            record_language_regions(layout[:rule_row], code_label(@source_lang), code_label(@target_lang))
            record_paste_region(layout[:rule_row], width)
            record_close_region(layout[:rule_row], width)
          end

          # Anchored at the bar and grown upward: rule · source well · divider · target.
          # The card hugs its content but never shrinks below a comfortable workspace,
          # and never grows past its height ceiling (then each region scrolls).
          def editor_layout(bounds, width, source_count, target_count)
            bottom_row = bounds.height - 1
            return nil if bounds.width < MIN_WIDTH || bottom_row < 6

            _, constrained = fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH)
            max_total = [constrained ? MAX_ROWS_TALL : MAX_ROWS, bottom_row].min
            source_need = [source_count, MIN_SOURCE_ROWS].max
            target_need = [target_count, MIN_TARGET_ROWS].max
            total = [2 + source_need + target_need, max_total].min
            source_rows, target_rows = split_regions(total - 2, source_need, target_need)
            rule_row = bottom_row - total + 1
            return nil if rule_row < 1

            { col: 1, width: width, bottom_row: bottom_row, rule_row: rule_row,
              source_rows: source_rows, divider_row: rule_row + source_rows + 1, target_rows: target_rows }
          end

          def split_regions(content, source_need, target_need)
            return [source_need, target_need] if source_need + target_need <= content

            src = ((content * source_need).to_f / (source_need + target_need)).round.clamp(1, content - 1)
            [src, content - src]
          end

          # ----- source well -----

          def render_source(surface, bounds, layout, width, text_width, rows)
            cursor_row, cursor_col = cursor_location(rows)
            top = scroll_to_cursor(rows.length, layout[:source_rows], cursor_row)
            layout[:source_rows].times do |slot|
              idx = top + slot
              line = source_line(rows[idx], text_width, idx == cursor_row ? cursor_col : nil, slot)
              surface.write(bounds, layout[:rule_row] + 1 + slot, layout[:col], padded_field(line, width))
            end
          end

          # A single row of the source well. An empty buffer shows a dim placeholder on
          # the first row (blank field rows below it); otherwise the row's text, with
          # the caret rendered as an emerald block over the character it sits on (or a
          # block space when it sits past the row's end).
          def source_line(row, text_width, caret_col, slot)
            return field_seg(placeholder_text(text_width), Palette::TRANS_PLACEHOLDER_FG) if @query.empty? && slot.zero?
            return field_seg('', Palette::TRANS_INPUT_FG) if row.nil?

            text_with_caret(row[:text].to_s, text_width, caret_col)
          end

          # The cursor row: the source text with the same blinking thin-stripe caret
          # the annotation editor uses (Ui::CursorBlink), inserted at the caret column.
          def text_with_caret(text, text_width, caret_col)
            styled = field_seg(text, Palette::TRANS_INPUT_FG)
            return truncate(styled, text_width) if caret_col.nil?

            inline_cursor_text(
              styled, caret_col, width: text_width,
                                 style_prefix: "#{Palette::TRANS_FIELD_BG}#{Palette::TRANS_CARET_FG}",
                                 restore_prefix: "#{Palette::TRANS_FIELD_BG}#{Palette::TRANS_INPUT_FG}"
            )
          end

          def placeholder_text(text_width)
            truncate('Type or paste text to translate…', text_width)
          end

          # Wrap a styled field line in the inset well background, left-pad, right-pad.
          def padded_field(line, width)
            pad = [width - PAD - visible_length(line), 0].max
            "#{field_seg(' ' * PAD, Palette::TRANS_INPUT_FG)}#{line}" \
              "#{field_seg(' ' * pad, Palette::TRANS_INPUT_FG)}#{Palette::RESET}"
          end

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

          # Prefer the *next* row when the caret sits exactly on a wrap boundary, so it
          # reads as "start of the next line" rather than "past the end of this one".
          def crosses_into_next?(rows, index)
            nxt = rows[index + 1]
            return false unless nxt

            @cursor == nxt[:start] && @cursor != rows[index][:start]
          end

          def scroll_to_cursor(total, visible, cursor_row)
            return 0 if total <= visible

            top = cursor_row - visible + 1
            top.clamp(0, total - visible)
          end

          # ----- divider -----

          # A full-width labeled hairline separating the source well from the
          # translation, naming the target language: "──────── ↓ German ────────".
          # Once there is a translation, the right end carries the clickable Copy
          # button: "──── ↓ German ──── [ Copy ]".
          def render_divider(surface, bounds, row, width)
            record_copy_region(row, width)
            name = LanguageDirectory.name_for(@target_lang)
            chip_cols = @copy_region ? BUTTON_WIDTH + 1 : 0
            label_width = visible_length(" ↓ #{name} ")
            dashes = [width - label_width - chip_cols, 2].max
            left = dashes / 2
            rule = Palette::TRANS_RULE_FG
            emerald = Palette::TRANS_ACCENT_FG
            text = "#{seg('─' * left, rule)}#{seg(' ↓ ', emerald)}#{seg(name, "#{Palette::BOLD}#{emerald}")}" \
                   "#{seg(' ', rule)}#{seg('─' * (dashes - left), rule)}#{divider_copy_chip}#{Palette::RESET}"
            surface.write(bounds, row, 1, text)
          end

          # The Copy button plus a one-space gap, drawn flush to the divider's right
          # end; empty until there is a translation to copy.
          def divider_copy_chip
            return '' unless @copy_region

            "#{seg(' ', Palette::TRANS_RULE_FG)}#{copy_button_span}"
          end

          # ----- translation pane -----

          # Fills the whole translation region (blank rows included) so the card reads
          # as one solid panel down to the bar, never leaving holes under a short
          # translation.
          def render_target(surface, bounds, layout, width, lines)
            layout[:target_rows].times do |offset|
              line = lines[@scroll + offset]
              surface.write(bounds, layout[:divider_row] + 1 + offset, layout[:col], body_line(line.to_s, width))
            end
            render_target_scroll_markers(surface, bounds, layout, lines.length)
          end

          def target_display_lines(width)
            return [dim_line('↵ to translate')] if @result.nil?
            return error_lines if translation_error?
            return [dim_line('No translation')] if translated_text.empty?

            lines = wrap(translated_text, width).map { |line| text_line(line) }
            lines << dim_line('↵ to re-translate') if stale?
            note = detected_note
            lines.push('', dim_line(note)) if note
            lines
          end

          def translated_text
            @result.translated_text.to_s.strip
          end

          def translation_error?
            @result.respond_to?(:error?) && @result.error?
          end

          def error_lines
            message = @result.error_message.to_s.strip
            message = 'Translation failed' if message.empty?
            [dim_line(message), dim_line('Is a LibreTranslate server running?')]
          end

          def stale?
            !@results_query.strip.empty? && @query.strip != @results_query.strip
          end

          def detected_note
            return nil unless @source_lang.strip.casecmp?(LanguageDirectory::AUTO)

            code = @result.respond_to?(:detected_source_lang) ? @result.detected_source_lang.to_s.strip : ''
            return nil if code.empty?

            "Detected: #{LanguageDirectory.name_for(code)}"
          end

          def render_target_scroll_markers(surface, bounds, layout, total)
            return unless total > layout[:target_rows]

            col = layout[:col] + layout[:width] - 1
            marker = "#{Palette::RESET}#{Palette::TRANS_BG}#{Palette::TRANS_DIM_FG}"
            surface.write(bounds, layout[:divider_row] + 1, col, "#{marker}▲") if @scroll.positive?
            surface.write(bounds, layout[:bottom_row], col, "#{marker}▼") if @scroll < total - layout[:target_rows]
          end

          # The editor rule's right-side affordances: the Paste button and, snug
          # against it, the red close (✕) box in the very corner — no gap between
          # them, no hairline cap after the box (the rule is drawn with right_cap: '').
          # The translator now closes only from this box (or Esc), never from a click
          # out in the book.
          def editor_meta
            ["#{paste_button_span}#{close_button_span}", BUTTON_WIDTH + CLOSE_WIDTH]
          end

          # ----- clickable action buttons (Paste on the rule, Copy on the divider) -----

          def paste_button_span
            button_span(paste_button_label, paste_button_background)
          end

          def copy_button_span
            button_span(copy_button_label, copy_button_background)
          end

          def paste_button_label
            feedback_active?(:pasted) ? PASTED_LABEL : PASTE_LABEL
          end

          def copy_button_label
            feedback_active?(:copied) ? COPIED_LABEL : COPY_LABEL
          end

          # Three states, mirroring the list rows: at rest, under the pointer
          # (hover), and on click / during the confirmation flash (active).
          def paste_button_background
            return Palette::TRANS_BUTTON_ACTIVE_BG if feedback_active?(:pasted)
            return Palette::TRANS_BUTTON_HOVER_BG if @hover_index == :paste_source

            Palette::TRANS_BUTTON_BG
          end

          def copy_button_background
            return Palette::TRANS_BUTTON_ACTIVE_BG if feedback_active?(:copied)
            return Palette::TRANS_BUTTON_HOVER_BG if @hover_index == :copy_translation

            Palette::TRANS_BUTTON_BG
          end

          # The red close box: a "✕" framed by a padding space each side, brightening
          # under the pointer like the other buttons.
          def close_button_span
            background = @hover_index == :translator_close ? Palette::TRANS_CLOSE_HOVER_BG : Palette::TRANS_CLOSE_BG
            cell(" #{CLOSE_GLYPH} ", "#{Palette::BOLD}#{Palette::TRANS_CLOSE_FG}", background)
          end

          # A filled, fixed-width button: the label centred in BUTTON_TEXT_WIDTH with
          # a padding space each side, so its width never changes with the label.
          def button_span(label, background)
            cell(" #{center_label(label, BUTTON_TEXT_WIDTH)} ", "#{Palette::BOLD}#{Palette::TRANS_BUTTON_FG}",
                 background)
          end

          def center_label(label, width)
            pad = [width - visible_length(label), 0].max
            left = pad / 2
            "#{' ' * left}#{label}#{' ' * (pad - left)}"
          end

          # The button's confirmation flash is on while its expiry is in the future;
          # the editor's continuous caret redraw reverts it once it lapses.
          def feedback_active?(kind)
            @feedback && @feedback[:kind] == kind && monotonic_now < @feedback[:until]
          end

          def normalize_feedback(value)
            return nil unless value.is_a?(Hash)

            normalized = value.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
            kind = normalized[:kind]
            kind = kind.to_sym if kind.respond_to?(:to_sym)
            expiry = normalized[:until]
            return nil unless kind && expiry

            { kind: kind, until: expiry.to_f }
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          # The right span on the rule is "Paste✕", flush to the corner with no cap:
          # the close box owns the last CLOSE_WIDTH columns and Paste sits immediately
          # to its left. Both widths are fixed, so neither click target shifts as the
          # Paste label flips to "Pasted!".
          def record_paste_region(row, width)
            paste_end = width - CLOSE_WIDTH # snug against the close box, no gap
            @paste_region = { row: row, cols: ((paste_end - BUTTON_WIDTH + 1)..paste_end) }
          end

          def record_close_region(row, width)
            @close_region = { row: row, cols: ((width - CLOSE_WIDTH + 1)..width) }
          end

          def record_copy_region(row, width)
            return unless copyable?

            @copy_region = { row: row, cols: ((width - BUTTON_WIDTH + 1)..width) }
          end

          def action_region(column, row)
            return :translator_close if region_hit?(@close_region, column, row)
            return :paste_source if region_hit?(@paste_region, column, row)
            return :copy_translation if region_hit?(@copy_region, column, row)

            nil
          end

          def region_hit?(region, column, row)
            region && row.to_i == region[:row] && region[:cols].cover?(column.to_i)
          end

          # True when there is a real translation on screen to copy.
          def copyable?
            !@result.nil? && !translation_error? && !translated_text.empty?
          end

          # ----- language-picker mode -----

          def render_picker(surface, bounds)
            width = card_width(bounds)
            candidates = picker_candidates
            layout = dock_layout(bounds, [candidates.length, 1].max)
            return unless layout

            ensure_candidate_visible!(candidates.length, layout[:visible])
            record_overlay_geometry(
              rule_row: layout[:rule_row], col: layout[:col], width: width,
              visible: layout[:visible], rows_per: 1,
              scroll: @picker_scroll, count: candidates.length
            )
            record_language_regions(layout[:rule_row], SOURCE_LABEL, TARGET_LABEL)
            render_rule(surface, bounds, layout[:rule_row], layout[:width],
                        picker_headword_spans, picker_meta(candidates.length))
            render_candidates(surface, bounds, layout, candidates, width)
          end

          def render_candidates(surface, bounds, layout, candidates, width)
            if candidates.empty?
              empty = body_line(dim_line('No languages match'), width)
              surface.write(bounds, layout[:rule_row] + 1, layout[:col], empty)
              return
            end

            scrollbar = candidates.length > layout[:visible]
            render_picker_scrollbar(surface, bounds, layout, candidates.length) if scrollbar
            text_width = width - (scrollbar ? SCROLLBAR_WIDTH : 0)
            layout[:visible].times do |slot|
              idx = @picker_scroll + slot
              lang = candidates[idx]
              next unless lang

              row = candidate_row(lang, text_width, idx == @picker_index, hovered_candidate?(idx, candidates.length))
              surface.write(bounds, layout[:rule_row] + 1 + slot, layout[:col], row)
            end
          end

          def hovered_candidate?(absolute, count)
            !@hover_index.nil? && absolute == @hover_index && absolute != @picker_index &&
              absolute.between?(0, count - 1)
          end

          def candidate_background(selected, hovered)
            return Palette::TRANS_SELECTED_BG if selected
            return Palette::TRANS_HOVER_BG if hovered

            Palette::TRANS_BG
          end

          def candidate_row(lang, width, selected, hovered)
            background = candidate_background(selected, hovered)
            current = active_side_lang.casecmp?(lang[:code].to_s)
            mark = marker(selected, current)
            code = ljust(lang[:code].to_s.upcase, CODE_WIDTH)
            name_room = [width - visible_length(mark) - CODE_WIDTH - 1 - RIGHT_GAP, 4].max
            name = truncate(lang[:name].to_s, name_room)
            pad = [name_room - visible_length(name), 0].max + RIGHT_GAP

            "#{cell(mark, marker_fg(selected, current), background)}" \
              "#{cell(code, Palette::TRANS_CODE_FG, background)}#{cell(' ', Palette::TRANS_DIM_FG, background)}" \
              "#{cell(name, name_fg(current), background)}#{cell(' ' * pad, Palette::TRANS_DIM_FG, background)}" \
              "#{Palette::RESET}"
          end

          def marker(selected, current)
            return POINTER if selected
            return CURRENT_MARK if current

            BLANK_MARK
          end

          def marker_fg(selected, current)
            return Palette::TRANS_POINTER_FG if selected
            return Palette::TRANS_ACCENT_FG if current

            Palette::TRANS_DIM_FG
          end

          def name_fg(current)
            current ? Palette::TRANS_ACCENT_FG : Palette::TRANS_LANG_FG
          end

          def picker_candidates
            LanguageDirectory.candidates_for(@languages, side: @picker_side, query: @picker_query)
          end

          def active_side_lang
            (@picker_side == :source ? @source_lang : @target_lang).to_s
          end

          # Picker headword: "Source ▸ Target" with the active side in emerald-bold,
          # plus the live filter as a caret-tailed query when one is being typed.
          def picker_headword_spans
            src = side_chip(SOURCE_LABEL, @picker_side == :source)
            tgt = side_chip(TARGET_LABEL, @picker_side == :target)
            sep = seg(" #{ARROW} ", Palette::TRANS_DIM_FG)
            base = "#{src[:span]}#{sep}#{tgt[:span]}"
            base_len = src[:len] + visible_length(" #{ARROW} ") + tgt[:len]
            return [base, base_len] if @picker_query.empty?

            filter = "  #{@picker_query}▏"
            ["#{base}#{seg(filter, Palette::TRANS_INPUT_FG)}", base_len + visible_length(filter)]
          end

          # The two language tabs on the picker rule. The active side (whose list is
          # open) is a raised, brightly-lit fill so it reads as the foreground; the
          # other tab is a recessed, dim fill so it sits back in the background. The
          # label width is unchanged, so the click regions stay put as the side flips.
          def side_chip(label, active)
            span = if active
                     cell(label, "#{Palette::BOLD}#{Palette::TRANS_TEXT_FG}", Palette::TRANS_TAB_ACTIVE_BG)
                   else
                     cell(label, Palette::TRANS_DIM_FG, Palette::TRANS_TAB_INACTIVE_BG)
                   end
            { span: span, len: visible_length(label) }
          end

          def picker_meta(count)
            current = LanguageDirectory.name_for(active_side_lang)
            label = "now #{current} · #{count}"
            [seg(label, Palette::TRANS_DIM_FG), visible_length(label)]
          end

          def render_picker_scrollbar(surface, bounds, layout, total_items)
            rows = layout[:visible]
            thumb = scrollbar_thumb(rows, total_items)
            top = layout[:rule_row] + 1
            col = layout[:col] + layout[:width] - 1
            rows.times do |offset|
              in_thumb = offset >= thumb[:start] && offset < thumb[:start] + thumb[:size]
              color = in_thumb ? Palette::TRANS_SCROLL_THUMB_FG : Palette::TRANS_SCROLL_TRACK_FG
              surface.write(bounds, top + offset, col, "#{Palette::RESET}#{Palette::TRANS_BG}#{color}#{SCROLL_GLYPH}")
            end
          end

          def scrollbar_thumb(rows, total_items)
            total = [total_items, 1].max
            size = (rows.to_f / total * rows).round.clamp(1, rows)
            room = rows - size
            denom = [total - rows, 1].max
            start = room <= 0 ? 0 : ((@picker_scroll.to_f / denom) * room).round.clamp(0, room)
            { size: size, start: start }
          end

          def ensure_candidate_visible!(total, visible)
            @picker_index = @picker_index.clamp(0, [total - 1, 0].max)
            if @picker_index < @picker_scroll
              @picker_scroll = @picker_index
            elsif @picker_index >= @picker_scroll + visible
              @picker_scroll = @picker_index - visible + 1
            end
            @picker_scroll = @picker_scroll.clamp(0, [total - visible, 0].max)
          end

          # ----- shared geometry + drawing -----

          def card_width(bounds)
            fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH).first
          end

          # Top hairline rule: "── <left> ········· <right> ──" from pre-styled
          # [span, visible_length] pairs. The editor face passes right_cap: '' so its
          # close box sits flush in the top-right corner with no trailing hairline.
          def render_rule(surface, bounds, row, width, left, right, right_cap: ' ──')
            return if row < 1

            left_span, left_len = left
            right_span, right_len = right
            rule_fg = Palette::TRANS_RULE_FG
            fill = [width - left_len - right_len - right_cap.length - 5, 1].max

            text = "#{seg('── ', rule_fg)}#{left_span}#{seg(" #{'·' * fill} ", rule_fg)}" \
                   "#{right_span}#{seg(right_cap, rule_fg)}#{Palette::RESET}"
            surface.write(bounds, row, 1, text)
          end

          # Record the screen columns the source/target labels occupy on the rule,
          # so a click on either one opens (editor) or flips to (picker) that side.
          # The rule is "── <src> → <tgt> ···": "── " is 3 columns, then the source
          # label, a space, the arrow, a space, then the target label — all
          # single-width — so the columns are the same for the editor's codes
          # (AUTO/EN) and the picker's words (Source/Target).
          def record_language_regions(row, src_label, tgt_label)
            source_start = 4 # after the leading "── " (cols 1-3)
            target_start = source_start + src_label.length + 3 # + space + arrow + space
            @lang_regions = {
              row: row,
              source: (source_start..(source_start + src_label.length - 1)),
              target: (target_start..(target_start + tgt_label.length - 1)),
            }
          end

          def language_region(column, row)
            regions = @lang_regions
            return nil unless regions && row.to_i == regions[:row]

            return :picker_source if regions[:source].cover?(column.to_i)
            return :picker_target if regions[:target].cover?(column.to_i)

            nil
          end

          # The language pair for the editor rule: "EN →(emerald) DE".
          def pair_spans
            src = code_label(@source_lang)
            tgt = code_label(@target_lang)
            plain = "#{src} #{ARROW} #{tgt}"
            code_style = "#{Palette::BOLD}#{Palette::TRANS_CODE_FG}"
            styled = "#{seg(src, code_style)}#{seg(' ', Palette::TRANS_DIM_FG)}" \
                     "#{seg(ARROW, Palette::TRANS_ACCENT_FG)}#{seg(' ', Palette::TRANS_DIM_FG)}#{seg(tgt, code_style)}"
            [styled, visible_length(plain)]
          end

          def code_label(code)
            code.to_s.strip.casecmp?(LanguageDirectory::AUTO) ? 'AUTO' : code.to_s.strip.upcase
          end

          # A translation/body line over the panel background: a left margin matching
          # the source text, then the (already-styled) line, padded out to the width.
          def body_line(text, width)
            base = "#{Palette::RESET}#{Palette::TRANS_BG}#{Palette::TRANS_TEXT_FG}"
            safe = text.to_s.gsub(Palette::RESET, base)
            pad = [width - PAD - visible_length(safe), 0].max
            "#{base}#{' ' * PAD}#{safe}#{' ' * pad}#{Palette::RESET}"
          end

          def text_line(text)
            "#{Palette::TRANS_TEXT_FG}#{text}"
          end

          def dim_line(text)
            "#{DIM}#{Palette::TRANS_DIM_FG}#{text}#{STYLE_RESET}"
          end

          def seg(text, foreground)
            "#{Palette::RESET}#{Palette::TRANS_BG}#{foreground}#{text}"
          end

          def field_seg(text, foreground)
            "#{Palette::RESET}#{Palette::TRANS_FIELD_BG}#{foreground}#{text}"
          end

          def cell(text, foreground, background)
            "#{Palette::RESET}#{background}#{foreground}#{text}"
          end

          # Word-wrap that honors hard newlines (Shift/Alt+Enter) and preserves every
          # character (the break space rides the end of its line), recording each row's
          # start index so the flat caret can be mapped onto a (row, column). Each "\n"
          # forces a new row and is consumed as the break. Returns [{ text:, start: }].
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

          # Wrap one physical line [start, line_end) into rows; always adds at least one
          # row (empty for a blank line), and returns line_end.
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
            take = brk && brk.positive? ? brk + 1 : width
            rows << { text: text[cursor, take], start: cursor }
            cursor + take
          end

          # Plain word-wrap (translation pane); honors hard newlines.
          def wrap(text, width)
            width = [width.to_i, 1].max
            text.to_s.split("\n").flat_map { |paragraph| wrap_paragraph(paragraph, width) }
          end

          def wrap_paragraph(paragraph, width)
            words = paragraph.strip.split(/\s+/)
            return [''] if words.empty?

            words.each_with_object([]) do |word, lines|
              if lines.empty? || visible_length("#{lines.last} #{word}") > width
                lines.concat(split_long_word(word, width))
              else
                lines[-1] = "#{lines.last} #{word}"
              end
            end
          end

          def split_long_word(word, width)
            return [word] if visible_length(word) <= width

            word.chars.each_with_object(['']) do |char, lines|
              if visible_length("#{lines.last}#{char}") > width
                lines << char
              else
                lines[-1] = "#{lines.last}#{char}"
              end
            end
          end

          def ljust(text, width)
            pad = [width - visible_length(text), 0].max
            "#{text}#{' ' * pad}"
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
