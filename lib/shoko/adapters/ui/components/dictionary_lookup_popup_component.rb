# frozen_string_literal: true

require_relative 'base_component'
require_relative 'bottom_left_panel'
require_relative 'overlay_mouse_target'
require_relative 'ui/panel_spans'
require_relative 'ui/list_helpers'
require_relative 'dictionary/entry_formatter'
require 'shoko/shared/terminal/text_metrics'
require_relative 'status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        # The reader dictionary "Definition card": a left-anchored panel docked
        # directly onto the bottom status bar (which hosts the "Dictionary/<format>"
        # input). It snaps flush to the left edge and the bar — no floating gap —
        # while keeping a capped width on the right, and grows upward. The
        # dictionary's tailored cousin of the in-book search results list.
        #
        # Same form factor as InBookSearchPopupComponent (a pure renderer that
        # owns no query/result state and re-renders from the reader view-state
        # store each frame), but a distinct teal identity. The headword rides the
        # top hairline rule; the part-of-speech, numbered senses, and translations
        # flow below it. In fuzzy mode it becomes a selectable candidate list.
        # ↑/↓ scroll/select via `dictionary_selected_index`, written app-side.
        class DictionaryLookupPopupComponent < BaseComponent
          include BottomLeftPanel
          include OverlayMouseTarget
          include Ui::PanelSpans

          Palette = StatusBar::Palette

          MAX_ROWS = 12      # row ceiling when the card keeps its natural width
          MAX_ROWS_TALL = 18 # taller ceiling when it shrinks to the left margin
          MAX_WIDTH = 76
          MIN_WIDTH = 30
          POINTER = '▸ '

          attr_reader :result, :entry_index, :selected_index, :fuzzy_mode

          def initialize(reader_state_reader:, color_mode: :dark)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = color_mode
            @result = nil
            @entry_index = 0
            @selected_index = 0
            @fuzzy_mode = false
            @fuzzy_matches = []
            @query = ''
            @scroll = 0
            @fuzzy_scroll = 0
          end

          def visible?
            @reader_state_reader&.mode == :dictionary
          end

          # Theme-independent (fixed teal palette, like the bar); kept for parity
          # with the session's refresh_theme call.
          def update_color_mode(mode)
            @color_mode = mode
          end

          def do_render(surface, bounds)
            clear_overlay_geometry
            return unless visible?

            sync_from_state
            return if @result.nil?

            @fuzzy_mode ? render_fuzzy(surface, bounds) : render_entry(surface, bounds)
          end

          private

          # Refresh the render cache from the observable dictionary state each frame.
          def sync_from_state
            reader = @reader_state_reader
            @result = reader&.dictionary_result
            @entry_index = (reader&.dictionary_entry_index || 0).to_i
            @selected_index = (reader&.dictionary_selected_index || 0).to_i
            @hover_index = reader&.overlay_hover_index
            @fuzzy_mode = reader&.dictionary_fuzzy_mode == true
            @fuzzy_matches = Array(reader&.dictionary_fuzzy_matches)
            @query = (reader&.dictionary_query || '').to_s
          end

          def hovered_candidate?(absolute)
            !@hover_index.nil? && absolute == @hover_index && absolute != @selected_index &&
              absolute.between?(0, @fuzzy_matches.length - 1)
          end

          # ----- entry (definition) mode -----

          def render_entry(surface, bounds)
            render_card(surface, bounds, entry_headword, entry_meta, body_lines(card_width(bounds)))
          end

          # A scrolling text card: the headword on the rule, then a window of
          # formatted body lines anchored to the bar, growing upward.
          def render_card(surface, bounds, headword, meta, lines)
            width = card_width(bounds)
            layout = dock_layout(bounds, lines.length)
            return unless layout

            # A definition card has no clickable rows; record it (count 0) so a
            # click in the book above still dismisses while clicks on it are inert.
            record_overlay_geometry(
              rule_row: layout[:rule_row], col: layout[:col], width: width,
              visible: 0, rows_per: 1, scroll: 0, count: 0
            )
            clamp_scroll!(lines.length, layout[:visible])
            render_rule(surface, bounds, layout, headword, meta)
            window = lines[@scroll, layout[:visible]] || []
            window.each_with_index do |line, offset|
              surface.write(bounds, layout[:rule_row] + 1 + offset, layout[:col], body_line(line, width))
            end
            render_scroll_markers(surface, bounds, layout, lines.length)
          end

          def body_lines(width)
            return unavailable_lines if @result.search_mode == :unavailable
            return error_lines if @result.search_mode == :error
            return not_found_lines if @result.empty?

            entry = selected_entry
            entry ? formatter(width).format_entry_body(entry) : not_found_lines
          end

          def selected_entry
            entries = Array(@result.entries)
            return nil if entries.empty?

            entries[@entry_index % entries.length]
          end

          def entry_headword
            (selected_entry&.word || @result.query).to_s
          end

          def entry_meta
            parts = []
            pair = pair_label
            parts << pair if pair
            count = @result.entry_count
            parts << "#{(@entry_index % [count, 1].max) + 1}/#{count}" if count > 1
            parts.join(' · ')
          end

          def not_found_lines
            [dim_line('No entry found'), '', dim_line('Press f to search similar words')]
          end

          def unavailable_lines
            [dim_line('Dictionary not installed for this pair'), '', dim_line('Press Esc, then install via Settings')]
          end

          def error_lines
            message = @result.error_message.to_s.strip
            [dim_line(message.empty? ? 'Lookup failed — please try again' : message)]
          end

          def formatter(width)
            Dictionary::EntryFormatter.new(
              width: [width - 1, 12].max,
              background: Palette::DICT_BG,
              color_mode: @color_mode,
              accent: Palette::DICT_TRANS_FG
            )
          end

          # ----- fuzzy candidate mode -----

          def render_fuzzy(surface, bounds)
            if @fuzzy_matches.empty?
              render_card(surface, bounds, @query, 'no similar', [dim_line('No similar words found')])
              return
            end

            width = card_width(bounds)
            layout = dock_layout(bounds, @fuzzy_matches.length)
            return unless layout

            ensure_candidate_visible!(layout[:visible])
            record_overlay_geometry(
              rule_row: layout[:rule_row], col: layout[:col], width: width,
              visible: layout[:visible], rows_per: 1,
              scroll: @fuzzy_scroll, count: @fuzzy_matches.length
            )
            render_rule(surface, bounds, layout, @query, "#{@fuzzy_matches.length} similar")
            layout[:visible].times do |offset|
              idx = @fuzzy_scroll + offset
              match = @fuzzy_matches[idx]
              next unless match

              line = candidate_line(match, width, idx == @selected_index, hovered_candidate?(idx))
              surface.write(bounds, layout[:rule_row] + 1 + offset, layout[:col], line)
            end
          end

          def candidate_line(match, width, selected, hovered)
            bg = candidate_background(selected, hovered)
            pct = "#{(match.similarity * 100).round}%"
            word_width = [width - visible_length(POINTER) - visible_length(pct) - 2, 4].max
            word = truncate(match.word.to_s, word_width)
            gap = [width - visible_length(POINTER) - visible_length(word) - visible_length(pct), 1].max

            "#{candidate_pointer(selected, bg)}#{cell(word, Palette::DICT_HEADWORD_FG, bg)}" \
              "#{cell(' ' * gap, Palette::DICT_DIM_FG, bg)}#{cell(pct, Palette::DICT_NUM_FG, bg)}#{Palette::RESET}"
          end

          def candidate_background(selected, hovered)
            return Palette::DICT_SELECTED_BG if selected
            return Palette::DICT_HOVER_BG if hovered

            Palette::DICT_BG
          end

          def candidate_pointer(selected, background)
            return cell(POINTER, Palette::DICT_POINTER_FG, background) if selected

            cell('  ', Palette::DICT_DIM_FG, background)
          end

          def ensure_candidate_visible!(visible)
            @selected_index = @selected_index.clamp(0, [@fuzzy_matches.length - 1, 0].max)
            @fuzzy_scroll = Ui::ListHelpers.scroll_to_reveal(
              @selected_index, scroll: @fuzzy_scroll, visible: visible, total: @fuzzy_matches.length
            )
          end

          # ----- shared geometry + drawing -----

          # The card shrinks to the reader's empty left margin when one exists, so
          # narrow centered text wraps into a taller card instead of a wide one
          # that overlaps the prose; otherwise it keeps its natural width.
          def card_width(bounds)
            fit_to_left_margin(bounds, MIN_WIDTH, MAX_WIDTH).first
          end

          # Top hairline rule: "── headword ·········· pair · n/total ──".
          def render_rule(surface, bounds, layout, headword, meta)
            row = layout[:rule_row]
            return if row < 1

            surface.write(bounds, row, layout[:col], rule_text(headword.to_s, meta.to_s, layout[:width]))
          end

          def rule_text(headword, meta, width)
            prefix = '── '
            suffix = ' ──'
            head = truncate(headword, [width - visible_length(prefix) - visible_length(suffix) - 8, 4].max)
            fill = [width - visible_length(prefix) - visible_length(head) - visible_length(meta) -
              visible_length(suffix) - 2, 1].max
            rule_fg = Palette::DICT_RULE_FG

            "#{seg(prefix, rule_fg)}#{seg(head, "#{Palette::BOLD}#{Palette::DICT_HEADWORD_FG}")}" \
              "#{seg(" #{'·' * fill} ", rule_fg)}#{seg(meta, Palette::DICT_DIM_FG)}#{seg(suffix, rule_fg)}#{Palette::RESET}"
          end

          def render_scroll_markers(surface, bounds, layout, total)
            return unless total > layout[:visible]

            col = layout[:col] + layout[:width] - 1
            marker = "#{Palette::RESET}#{Palette::DICT_BG}#{Palette::DICT_DIM_FG}"
            surface.write(bounds, layout[:rule_row] + 1, col, "#{marker}▲") if @scroll.positive?
            surface.write(bounds, layout[:bottom_row], col, "#{marker}▼") if @scroll < total - layout[:visible]
          end

          def clamp_scroll!(total, visible)
            max = [total - visible, 0].max
            @scroll = @selected_index.clamp(0, max)
          end

          # PanelSpans palette hooks. The dim face relies on the surrounding
          # panel style, so panel_dim_fg stays empty.
          def panel_bg = Palette::DICT_BG
          def panel_dim_fg = ''
          def panel_body_fg = Palette::DICT_SENSE_FG

          def pair_label
            src = @result.source_lang.to_s.strip
            tgt = @result.target_lang.to_s.strip
            return nil if src.empty? && tgt.empty?

            "#{src.empty? ? '?' : src.downcase}→#{tgt.empty? ? '?' : tgt.downcase}"
          end
        end
      end
    end
  end
end
