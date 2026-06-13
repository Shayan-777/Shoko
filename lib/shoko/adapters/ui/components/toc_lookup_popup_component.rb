# frozen_string_literal: true

require_relative 'base_component'
require_relative 'bottom_left_panel'
require_relative 'overlay_mouse_target'
require 'shoko/shared/terminal/text_metrics'
require_relative 'status_bar/palette'

module Shoko
  module Adapters
    module Ui
      module Components
        # The reader's Table-of-Contents panel: a left-anchored list docked directly
        # onto the bottom status bar (which hosts the "TOC/<format>" filter input). It
        # snaps flush to the left edge and the bar — no floating gap — keeps a capped
        # width on the right, and grows upward. The third member of the bar-anchored
        # family, alongside the in-book search results list and the dictionary card.
        #
        # Same form factor and slate surface as those two (a pure renderer that owns
        # no query/selection state and re-renders from the reader view-state store
        # each frame), with its own soft-lavender "you are here" signature. Because it
        # is an overlay rather than a split panel, the prose never recomposes: on a
        # wide screen the centered text leaves an empty left margin, and — like the
        # search list — the panel tucks into that margin and grows taller, becoming a
        # full-height column on the left; when the text fills the width it keeps its
        # natural width and overlaps the bottom of the page instead.
        #
        # Rows are the visible TOC entries published by the controller
        # (`toc_visible_entries`): each a Hash with :title, :level, :current,
        # :navigable. ↑/↓ move `toc_selected_index` (app-side); ⏎ jumps; Esc closes.
        class TocLookupPopupComponent < BaseComponent
          include BottomLeftPanel
          include OverlayMouseTarget

          Palette = StatusBar::Palette

          MAX_ROWS = 13      # row ceiling when the panel keeps its natural width
          MAX_ROWS_TALL = 24 # taller ceiling when it shrinks into the left margin
          MAX_WIDTH = 62
          MIN_WIDTH = 26
          SCROLLBAR_WIDTH = 1
          RIGHT_GAP = 1      # blank column kept to the right of the text
          INDENT_STEP = 2    # columns of indent per nesting level
          MAX_INDENT_LEVEL = 4
          POINTER = '▸ '
          CURRENT_MARK = '● '
          BLANK_MARK = '  '
          SCROLL_GLYPH = '█'

          attr_reader :entries, :selected_index, :query, :scroll_offset

          def initialize(reader_state_reader:, color_mode: :dark)
            super()
            @reader_state_reader = reader_state_reader
            @color_mode = color_mode
            @entries = []
            @selected_index = 0
            @query = ''
            @scroll_offset = 0
            @visible_rows = 1
          end

          def visible?
            @reader_state_reader&.mode == :toc
          end

          # Theme-independent (fixed slate palette, like the bar); kept for parity
          # with the session's refresh_theme call.
          def update_color_mode(mode)
            @color_mode = mode
          end

          def do_render(surface, bounds)
            clear_overlay_geometry
            return unless visible?

            sync_from_state
            return if @entries.empty?

            layout = dock_layout(bounds, @entries.length)
            return unless layout

            @visible_rows = layout[:visible]
            ensure_selection_visible!(@visible_rows)
            record_overlay_geometry(
              rule_row: layout[:rule_row], col: layout[:col], width: layout[:width],
              visible: layout[:visible], rows_per: 1,
              scroll: @scroll_offset, count: @entries.length
            )
            render_panel(surface, bounds, layout)
          end

          private

          # Refresh the render cache from the observable TOC state each frame.
          def sync_from_state
            reader = @reader_state_reader
            @entries = normalize_entries(reader&.toc_visible_entries)
            @selected_index = (reader&.toc_selected_index || 0).to_i
            @hover_index = reader&.overlay_hover_index
            @query = (reader&.toc_query || '').to_s
            clamp_selection!
          end

          def hovered_row?(absolute)
            !@hover_index.nil? && absolute == @hover_index && absolute != @selected_index &&
              absolute.between?(0, @entries.length - 1)
          end

          def render_panel(surface, bounds, layout)
            scrollbar = @entries.length > layout[:visible]
            render_rule(surface, bounds, layout)
            render_scrollbar(surface, bounds, layout) if scrollbar
            text_width = layout[:width] - (scrollbar ? SCROLLBAR_WIDTH : 0)
            layout[:visible].times do |slot|
              absolute = @scroll_offset + slot
              entry = @entries[absolute]
              next unless entry

              row = entry_row(entry, text_width, absolute == @selected_index, hovered_row?(absolute))
              surface.write(bounds, layout[:rule_row] + 1 + slot, layout[:col], row)
            end
          end

          # Top hairline rule framing the panel: "── Contents ········· 12 chapters ──".
          # The left label flips to a "↑ N more" hint when rows are scrolled off the top.
          def render_rule(surface, bounds, layout)
            row = layout[:rule_row]
            return if row < 1

            left = @scroll_offset.positive? ? "↑ #{@scroll_offset} more" : 'Contents'
            surface.write(bounds, row, layout[:col], rule_text(left, count_label, layout[:width]))
          end

          # Frame caps "── " and " ──" are 3 columns each; the leading/trailing
          # one-space padding around the dot fill accounts for the remaining 2.
          def rule_text(left, right, width)
            rule_fg = Palette::TOC_RULE_FG
            head = truncate(left, [width - 16, 4].max)
            dots = '·' * [width - visible_length(head) - visible_length(right) - 8, 1].max

            "#{seg('── ', rule_fg)}#{seg(head, Palette::TOC_DIM_FG)}#{seg(" #{dots} ", rule_fg)}" \
              "#{seg(right, Palette::TOC_DIM_FG)}#{seg(' ──', rule_fg)}#{Palette::RESET}"
          end

          def count_label
            chapters = @entries.count { |entry| entry[:navigable] }
            return "#{chapters} #{plural(chapters, 'match', 'matches')}" unless @query.strip.empty?

            "#{chapters} #{plural(chapters, 'chapter', 'chapters')}"
          end

          # One entry row: pointer/here-marker, level indentation, the title in its
          # level tone, padded with the panel background out to the text width. The
          # RIGHT_GAP keeps the text clear of the scrollbar/edge while the row's
          # background still fills that column, so the strip reads as one panel.
          def entry_row(entry, width, selected, hovered)
            background = row_background(selected, hovered)
            current = entry[:current] == true
            lead = row_lead(entry, selected, current, background)
            body = row_body(entry, current, width - lead[:width], background)

            "#{lead[:text]}#{body}#{Palette::RESET}"
          end

          def row_background(selected, hovered)
            return Palette::TOC_SELECTED_BG if selected
            return Palette::TOC_HOVER_BG if hovered

            Palette::TOC_BG
          end

          def row_lead(entry, selected, current, background)
            mark = marker(selected, current)
            indent = BLANK_MARK * level_indent(entry[:level])
            text = "#{cell(mark, marker_fg(selected, current), background)}" \
                   "#{cell(indent, Palette::TOC_FAINT_FG, background)}"
            { text: text, width: visible_length(mark) + visible_length(indent) }
          end

          def row_body(entry, current, room, background)
            text_room = [room - RIGHT_GAP, 1].max
            title = truncate(display_title(entry), text_room)
            pad = [text_room - visible_length(title), 0].max + RIGHT_GAP
            "#{cell(title, title_style(entry, current), background)}#{cell(' ' * pad, Palette::TOC_DIM_FG, background)}"
          end

          def marker(selected, current)
            return POINTER if selected
            return CURRENT_MARK if current

            BLANK_MARK
          end

          def marker_fg(selected, current)
            return Palette::TOC_POINTER_FG if selected
            return Palette::TOC_CURRENT_FG if current

            Palette::TOC_DIM_FG
          end

          def title_style(entry, current)
            return "#{Palette::BOLD}#{Palette::TOC_CURRENT_FG}" if current && entry[:level].to_i.zero?
            return Palette::TOC_CURRENT_FG if current
            return "#{Palette::BOLD}#{Palette::TOC_TITLE_FG}" if entry[:level].to_i.zero?
            return Palette::TOC_FAINT_FG unless entry[:navigable]
            return Palette::TOC_TITLE_FG if entry[:level].to_i == 1

            Palette::TOC_SUB_FG
          end

          def display_title(entry)
            title = entry[:title].to_s.strip
            title = 'Untitled' if title.empty?
            entry[:level].to_i.zero? ? title.upcase : title
          end

          def level_indent(level)
            level.to_i.clamp(0, MAX_INDENT_LEVEL)
          end

          # A slim scrollbar down the panel's right side: a full-height track in a
          # lighter tone with a brighter thumb sized to the visible slice — matching
          # the in-book search list.
          def render_scrollbar(surface, bounds, layout)
            rows = layout[:visible]
            thumb = scrollbar_thumb(rows)
            top = layout[:rule_row] + 1
            col = layout[:col] + layout[:width] - 1
            rows.times do |offset|
              in_thumb = offset >= thumb[:start] && offset < thumb[:start] + thumb[:size]
              color = in_thumb ? Palette::TOC_SCROLL_THUMB_FG : Palette::TOC_SCROLL_TRACK_FG
              surface.write(bounds, top + offset, col, "#{Palette::RESET}#{Palette::TOC_BG}#{color}#{SCROLL_GLYPH}")
            end
          end

          def scrollbar_thumb(rows)
            total = [@entries.length, 1].max
            size = (rows.to_f / total * rows).round.clamp(1, rows)
            room = rows - size
            denom = [total - rows, 1].max
            start = room <= 0 ? 0 : ((@scroll_offset.to_f / denom) * room).round.clamp(0, room)
            { size: size, start: start }
          end

          def ensure_selection_visible!(visible)
            if @selected_index < @scroll_offset
              @scroll_offset = @selected_index
            elsif @selected_index >= @scroll_offset + visible
              @scroll_offset = @selected_index - visible + 1
            end
            clamp_scroll!(visible)
          end

          def clamp_selection!
            @selected_index = @entries.empty? ? 0 : @selected_index.clamp(0, @entries.length - 1)
          end

          def clamp_scroll!(visible)
            max = [@entries.length - [visible, 1].max, 0].max
            @scroll_offset = @scroll_offset.clamp(0, max)
          end

          def normalize_entries(raw)
            Array(raw).filter_map do |entry|
              next unless entry.is_a?(Hash)

              {
                title: value(entry, :title).to_s,
                level: value(entry, :level).to_i,
                current: value(entry, :current) == true,
                navigable: value(entry, :navigable) != false,
              }
            end
          end

          def value(entry, key)
            return entry[key] if entry.key?(key)

            entry[key.to_s]
          end

          def plural(count, singular, plural)
            count == 1 ? singular : plural
          end

          # A span carrying its own complete style over the panel background.
          def cell(text, foreground, background)
            "#{Palette::RESET}#{background}#{foreground}#{text}"
          end

          def seg(text, foreground)
            "#{Palette::RESET}#{Palette::TOC_BG}#{foreground}#{text}"
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
