# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require_relative 'base_screen_component'
require_relative '../rect'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/canvas_well'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/spinner'
require_relative '../ui/text_utils'
require 'shoko/shared/prepagination_status'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/text_sanitizer'
require 'time'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Library — the cached shelf on the canvas: numbered rows with the
          # family's selection strip and a right-aligned "accessed ago" label;
          # books being re-paginated show an animated spinner or queued dot in
          # their number column. SPACE raises the inspector well — a raised
          # card carrying the selected book's metadata — beside the list,
          # separated from it purely by surface elevation.
          #
          # A title is never cut off: it flows onto as many rows as it needs,
          # indented under the number column and stopping a clear channel short
          # of the column the "accessed ago" labels right-align into — the
          # Browse shelf's grammar, applied to the cache. Rows therefore vary
          # in height, so the window is measured in rows rather than counted in
          # books.
          class LibraryScreenComponent < BaseScreenComponent
            TextSanitizer = Shoko::Shared::Terminal::TextSanitizer

            include Ui::TextUtils

            Palette = StatusBar::Palette

            Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path)

            TIME_INTERVALS = [
              { max: 3600, div: 60, singular: 'a minute ago', plural: '%d min ago' },
              { max: 86_400, div: 3600, singular: 'an hour ago', plural: '%d hours ago' },
              { max: 604_800, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
              { max: Float::INFINITY, div: 604_800, singular: 'a week ago', plural: '%d weeks ago' },
            ].freeze

            WELL_WIDTH = 34
            WELL_GAP = 2
            DETAIL_KEY_WIDTH = 10

            MARKER_WIDTH = 3 # the number / spinner / queued-dot column
            MARKER_GAP = 2 # the space after it, which wrapped title rows indent past
            MARKER_COLUMN = MARKER_WIDTH + MARKER_GAP
            ACCESSED_COLUMN = 12 # the right-hand column the "accessed ago" labels fill
            ACCESSED_GAP = 4 # the channel held clear between a row's text and that column
            STATUS_GAP = 2 # the space before the re-pagination note
            MIN_TITLE_WIDTH = 16

            Status = Shoko::Shared::PrepaginationStatus
            TextMetrics = Shoko::Shared::Terminal::TextMetrics
            Spinner = Shoko::Adapters::Ui::Components::Ui::Spinner

            def initialize(menu_state_reader: nil, catalog_service: nil, menu_hit_registry: nil,
                           menu_visual_profile: nil)
              super()
              @menu_state_reader = menu_state_reader
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
              @catalog = catalog_service
              @items = nil
              @row_lines = {}
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              @row_lines = {}
              items = load_items
              selected = selected_index(items.length)
              frame.render_rule(title: 'Library', accent: accent, meta: rule_meta(items))

              render_list(surface, bounds, frame, items: items, selected: selected)
              render_details_well(surface, bounds, frame, items[selected]) if details_open?
              frame.render_hint(hint_text)
            end

            def items
              load_items
            end

            def invalidate_cache!
              @items = nil
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:library)
            end

            def hits
              @menu_hit_registry
            end

            def rule_meta(items)
              "#{items.length} cached"
            end

            def hint_text
              return 'ENTER open · SPACE closes inspector · ESC back' if details_open?

              'ENTER open · SPACE inspects · wheel scrolls · ESC back'
            end

            def list_width(frame)
              return frame.content_width unless details_open?

              [frame.content_width - WELL_WIDTH - WELL_GAP, 24].max
            end

            def render_list(surface, bounds, frame, items:, selected:)
              top = frame.body_top
              height = frame.body_height
              return if height <= 0
              return render_empty(frame, top, height) if items.empty?

              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :library })
              width = title_column(list, frame)
              window = visible_window(selected: selected, budget: height, width: width)
              render_window(list, frame, window: window, top: top, width: width, selected: selected)
              render_overflow_scrollbar(list, window, top: top, height: height, total: items.length)
            end

            def render_window(list, frame, window:, top:, width:, selected:)
              row = top
              window[:indexes].each_with_index do |index, offset|
                lines = row_lines(index, width, selected)
                break if offset.positive? && row + lines.length - 1 > frame.body_bottom

                row += render_item_row(list, frame, lines: lines, index: index, row: row, selected: index == selected)
              end
            end

            # Draws one entry, clipped only by the body's last row — never by
            # cutting a title off. Returns the rows it consumed.
            def render_item_row(list, frame, lines:, index:, row:, selected:)
              visible = lines.first(frame.body_bottom - row + 1)
              list.block(row: row, lines: visible, selected: selected,
                         action: { type: :list_row, list: :library, index: index },
                         width: list_width(frame))
              visible.length
            end

            # The inspector well takes the list's right edge, and the scrollbar
            # with it.
            def render_overflow_scrollbar(list, window, top:, height:, total:)
              shown = window[:indexes].length
              return if details_open? || shown.zero? || total <= shown

              list.render_scrollbar(top: top, height: height, total: total,
                                    visible: shown, offset: window[:start])
            end

            def render_empty(frame, top, height)
              frame.write_line(top + [height / 2, 0].max - 1, [['No cached books yet', Palette::LANDING_DIM_FG]])
            end

            # ----- flowed rows -----

            # Rows for one cached book: the marker column, then the title
            # flowing between words onto as many rows as it needs, with the
            # re-pagination note trailing it and the "accessed ago" label
            # riding the first row.
            def item_rows(item, index, selected, width)
              status = prepagination_status_for(item)
              title_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              title_rows(title_of(item), status_label(status), width, title_fg).each_with_index.map do |row, offset|
                next { left: [[' ' * MARKER_COLUMN, nil], *row] } unless offset.zero?

                { left: [[row_marker(status, index), Palette::LANDING_DIM_FG], [' ' * MARKER_GAP, nil], *row],
                  right: [[accessed_label(item), Palette::LANDING_DIM_FG]] }
              end
            end

            # The title flows; the re-pagination note trails its last row,
            # dropping onto a row of its own when no room is left beside it.
            def title_rows(title, label, width, title_fg)
              rows = wrap_words(title, width).map { |line| [[line, title_fg]] }
              return rows if label.empty?
              return rows << [[label, accent]] unless label_fits?(rows.last, label, width)

              rows[-1] += [[' ' * STATUS_GAP, nil], [label, accent]]
              rows
            end

            def label_fits?(row, label, width)
              used = row.sum { |text, _fg| TextMetrics.visible_length(text.to_s) }
              used + STATUS_GAP + TextMetrics.visible_length(label) <= width
            end

            # A title stops a clear channel short of the "accessed ago" column,
            # so no title ever runs alongside a timestamp. A list too narrow to
            # afford the channel keeps its title text instead.
            def title_column(list, frame)
              available = [list.text_width(list_width(frame)) - MARKER_COLUMN, 1].max
              return available if available <= MIN_TITLE_WIDTH

              (available - ACCESSED_COLUMN - ACCESSED_GAP).clamp(MIN_TITLE_WIDTH, available)
            end

            # Rows are measured before they are drawn, so each visible book's
            # rows are laid out exactly once per frame.
            def row_lines(index, width, selected)
              @row_lines[index] ||= item_rows(load_items[index], index, index == selected, width)
            end

            def title_of(item)
              TextSanitizer.single_line(item.title.to_s.strip.empty? ? 'Untitled' : item.title)
            end

            # The label fills the column exactly, so the channel to its left
            # stays the same width on every row of the shelf.
            def accessed_label(item)
              pad_left(relative_accessed_label(item.last_accessed), ACCESSED_COLUMN)
            end

            # ----- the window, measured in rows -----

            def visible_window(selected:, budget:, width:)
              rows = [budget, 1].max
              start = window_start(selected, rows, width)
              { start: start, indexes: window_indexes(start: start, budget: rows, width: width, selected: selected) }
            end

            # The shelf's own scroll feel, retold for rows: it stays put while
            # everything down to the selection fits from the top, then anchors
            # the selection to the last row as the selection walks down.
            def window_start(selected, budget, width)
              return 0 if rows_through(selected, budget, width) <= budget

              start = selected
              used = row_lines(selected, width, selected).length
              while start.positive?
                height = row_lines(start - 1, width, selected).length
                break if used + height > budget

                used += height
                start -= 1
              end
              start
            end

            # Rows the entries down to the selection occupy, giving up once the
            # budget is blown — a long shelf is never measured end to end.
            def rows_through(selected, budget, width)
              total = 0
              (0..selected).each do |index|
                total += row_lines(index, width, selected).length
                break if total > budget
              end
              total
            end

            # As many whole entries as the row budget holds, from +start+ down.
            # The first is taken whatever its height: a book whose title alone
            # outgrows the list still has to be readable.
            def window_indexes(start:, budget:, width:, selected:)
              rows_left = budget
              (start...load_items.length).each_with_object([]) do |index, indexes|
                height = row_lines(index, width, selected).length
                break indexes if indexes.any? && height > rows_left

                rows_left -= height
                indexes << index
              end
            end

            # ----- inspector well -----

            def render_details_well(surface, bounds, frame, item)
              return unless item

              rect = well_rect(frame, bounds)
              return if rect.width < 20

              well = MenuDesign::CanvasWell.new(surface, bounds, rect: rect)
              well.paint(title: well.truncate(TextSanitizer.single_line(item.title || 'Untitled')), accent: accent)
              detail_lines(item, well.inner_width).each_with_index do |segments, offset|
                break if offset >= well.inner_height

                well.write_line(offset, segments)
              end
            end

            def well_rect(frame, bounds)
              width = [WELL_WIDTH, bounds.width - frame.content_x - 24].min
              Components::Rect.new(
                x: frame.content_x + frame.content_width - width,
                y: frame.body_top,
                width: width,
                height: [frame.body_height, 4].max
              )
            end

            def detail_lines(item, width)
              rows = []
              append_detail(rows, 'Authors', item.authors, width)
              append_detail(rows, 'Year', item.year, width)
              append_detail(rows, 'Accessed', relative_accessed_label(item.last_accessed), width)
              append_detail(rows, 'Size', format_size(item.size_bytes), width)
              append_detail(rows, 'Cache', compact_path(item.open_path), width)
              append_detail(rows, 'EPUB', compact_path(item.epub_path), width)
              rows
            end

            def append_detail(rows, label, value, width)
              safe_value = TextSanitizer.single_line(value.to_s.strip)
              safe_value = '—' if safe_value.empty?
              value_width = [width - DETAIL_KEY_WIDTH - 1, 8].max
              wrap_text(safe_value, value_width).each_with_index do |part, index|
                key = index.zero? ? pad_right("#{label}:", DETAIL_KEY_WIDTH) : (' ' * DETAIL_KEY_WIDTH)
                rows << [[key, Palette::LANDING_DIM_FG], [truncate_text(part, value_width), nil]]
              end
            end

            # ----- data + status helpers -----

            def load_items
              return @items if @items

              entries = Array(@catalog.cached_library_entries)
              @items = entries.map { |entry| build_item(entry) }
            end

            def build_item(entry)
              open_path = fetch_entry(entry, :open_path)
              Item.new(
                title: fetch_entry(entry, :title),
                authors: fetch_entry(entry, :authors),
                year: fetch_entry(entry, :year),
                last_accessed: fetch_entry(entry, :last_accessed),
                size_bytes: fetch_entry(entry, :size_bytes) || @catalog.size_for(open_path),
                open_path: open_path,
                epub_path: fetch_entry(entry, :epub_path)
              )
            end

            def fetch_entry(entry, key)
              return entry[key] if entry.is_a?(Struct)
              return entry.to_h[key] if entry.is_a?(Data)

              Shoko::Shared::HashNormalizer.symbolize_keys(entry)[key]
            end

            def selected_index(total)
              return 0 if total <= 0

              current = (menu_state_reader&.library_selected || 0).to_i
              current.clamp(0, total - 1)
            end

            def details_open?
              menu_state_reader&.library_details_open? == true
            end

            def prepagination_status_for(item)
              reader = menu_state_reader
              return Status::READY unless reader

              Status.for_path(
                item.epub_path,
                paths: reader.prepaginate_paths,
                done: reader.prepaginate_done,
                active: reader.prepaginate_active == true
              )
            end

            def row_marker(status, index)
              case status
              when Status::IN_PROGRESS then pad_left(Spinner.glyph, MARKER_WIDTH)
              when Status::QUEUED then pad_left(queued_glyph, MARKER_WIDTH)
              else pad_left((index + 1).to_s, MARKER_WIDTH)
              end
            end

            def status_label(status)
              case status
              when Status::IN_PROGRESS then '· recalculating'
              when Status::QUEUED then '· queued'
              else ''
              end
            end

            def queued_glyph
              Spinner.ascii_icons? ? 'o' : '◦'
            end

            def relative_accessed_label(iso)
              seconds = elapsed_seconds(iso)
              return '' unless seconds
              return 'just now' if seconds < 60

              interval = TIME_INTERVALS.find { |entry| seconds < entry[:max] }
              value = [seconds / interval[:div], 1].max
              value == 1 ? interval[:singular] : format(interval[:plural], value)
            end

            # Timestamps come from user-editable JSON; an unparseable one only
            # costs the "ago" label, never the row.
            def elapsed_seconds(iso)
              return nil if iso.to_s.empty?

              (Time.now - Time.parse(iso.to_s)).to_i
            rescue ArgumentError, TypeError => e
              swallow_timestamp_error(e)
            end

            def swallow_timestamp_error(_error)
              nil
            end

            def compact_path(path)
              value = path.to_s
              return '—' if value.empty?

              TextSanitizer.single_line(File.basename(value))
            end

            def format_size(bytes)
              format('%.1f MB', (bytes.to_f / (1024 * 1024)).round(1))
            end

            attr_reader :menu_state_reader
          end
        end
      end
    end
  end
end
