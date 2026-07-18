# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/text_sanitizer'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Browse — the searchable shelf, rendered in the canvas grammar as
          # the menu-side sibling of the in-book search list: roomy blocks
          # (title, then author · format, with the size right-aligned) wearing
          # the family's selection strip, a slim scrollbar when the shelf
          # overflows, and the search input living in the status bar exactly
          # like in-book search. A book being opened grows a progress row
          # under its block.
          #
          # Neither a title nor an author list is ever cut off: each flows onto
          # as many rows as it needs, stopping a clear channel short of the
          # column the sizes right-align into. Blocks therefore vary in height,
          # so the window is measured in rows rather than counted in books.
          class BrowseScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette

            ROWS_PER_BOOK = 2 # the shortest a block can be: one title row plus its meta row
            META_COLUMN = 9 # the right-hand column the size labels fill
            META_GAP = 4 # the channel held clear between a block's text and that column
            MIN_TEXT_WIDTH = 16
            UNREADABLE_METADATA = Object.new.freeze

            attr_reader :filtered_epubs

            def initialize(catalog_service, observer_registry, menu_state_reader: nil, menu_session_mutator: nil,
                           menu_hit_registry: nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @observer_registry = observer_registry
              @menu_state_reader = menu_state_reader
              @menu_session_mutator = menu_session_mutator
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
              @filtered_epubs = []
              @block_lines = {}

              # Re-filter the cached book list when the search query changes;
              # selection and search-mode flags are read live on render.
              @observer_registry.add_observer(self, %i[menu search_query])
            end

            def state_changed(_path, _old_value, _new_value)
              filter_books
            end

            def filtered_epubs=(books)
              @filtered_epubs = apply_search_filter(books || [], menu_state_reader&.search_query)
            end

            def selected
              menu_state_reader&.browse_selected
            end

            def navigate(key)
              return unless @filtered_epubs.any?

              current = selected_index(@filtered_epubs.length)
              max_index = @filtered_epubs.length - 1
              new_selected = case key
                             when :up then [current - 1, 0].max
                             when :down then [current + 1, max_index].min
                             else current
                             end
              menu_session_mutator&.update_menu(browse_selected: new_selected)
            end

            def selected_book
              @filtered_epubs[selected_index(@filtered_epubs.length)]
            end

            def filtered_count
              @filtered_epubs.length
            end

            def book_at(index)
              @filtered_epubs[index]
            end

            def do_render(surface, bounds)
              @filtered_epubs ||= []
              @block_lines = {}
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'Browse Library', accent: accent, meta: rule_meta)
              render_status_line(frame)
              render_books(surface, bounds, frame)
              frame.render_hint(hint_text)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:browse)
            end

            def hits
              @menu_hit_registry
            end

            def rule_meta
              total = @filtered_epubs.length
              "#{total} #{total == 1 ? 'book' : 'books'}"
            end

            # Scan feedback (or the active filter) rides a status line between
            # the rule and the list.
            def render_status_line(frame)
              left, left_fg = status_left
              right = filter_note
              return if left.empty? && right.empty?

              frame.render_status(row: frame.body_top, left: left, left_fg: left_fg, right: right)
            end

            def status_left
              message = sanitize_text(@catalog.scan_message)
              case @catalog.scan_status
              when :scanning
                [message.empty? ? 'Scanning for books…' : message, accent]
              when :error
                [message.empty? ? 'Scan failed' : message, Palette::LANDING_QUIT_FG]
              else
                ['', nil]
              end
            end

            def filter_note
              query = sanitize_text(menu_state_reader&.search_query)
              query.empty? ? '' : "filter: #{query}"
            end

            def render_books(surface, bounds, frame)
              list_top = list_top_row(frame)
              height = [frame.body_bottom - list_top + 1, 0].max
              return if height <= 0
              return render_empty(frame, list_top, height) if @filtered_epubs.empty?

              render_book_blocks(surface, bounds, frame, top: list_top, height: height)
            end

            def list_top_row(frame)
              status_present = @catalog.scan_status == :scanning || @catalog.scan_status == :error ||
                               !filter_note.empty?
              frame.body_top + (status_present ? 2 : 0)
            end

            def render_empty(frame, list_top, height)
              message = @catalog.scan_status == :scanning ? 'Scanning for books…' : 'No matching books'
              frame.write_line(list_top + [height / 2, 0].max - 1, [[message, Palette::LANDING_DIM_FG]])
            end

            def render_book_blocks(surface, bounds, frame, top:, height:)
              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              window = visible_window(list, height)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :browse })
              render_block_window(list, frame, window, top)
              render_overflow_scrollbar(list, top, height, window)
            end

            def render_block_window(list, frame, window, top)
              row = top
              window[:blocks].each_with_index do |block, offset|
                break if offset.positive? && row + block[:lines].length - 1 > frame.body_bottom

                row += render_book_block(list, frame, block: block, row: row,
                                                      selected: block[:index] == window[:selected])
              end
            end

            # Draws one block, plus the progress row a book being opened grows
            # underneath it; returns the rows the entry consumed. Only a block
            # taller than the whole body is clipped, and then by the body's own
            # last row — never by cutting a word off.
            def render_book_block(list, frame, block:, row:, selected:)
              lines = block[:lines].first(frame.body_bottom - row + 1)
              list.block(row: row, lines: lines, selected: selected,
                         action: { type: :list_row, list: :browse, index: block[:index] })
              return lines.length unless loading_for?(block[:book])

              render_loading_row(frame, row + lines.length)
              lines.length + 1
            end

            # Rows for one book: the bright title, then a dim author · format
            # line. Each breaks between words onto as many rows as it needs —
            # nothing on the shelf is ever cut off — which is why blocks vary
            # in height. The in-book search block shape, retold for the shelf.
            def book_block_rows(book, selected, width)
              title_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              title_rows = wrap_words(book_title(book), width).map { |line| { left: [[line, title_fg]] } }
              [*title_rows, *meta_rows(book, width)]
            end

            # The size label fills the metadata column exactly, so the channel
            # to its left stays the same width on every row of the shelf. It
            # rides the first row of the author line, however far that flows.
            def meta_rows(book, width)
              author = book_author(book)
              line = "#{author}#{' · ' unless author.empty?}#{file_format(book['path'])}"
              wrap_words(line, width).each_with_index.map do |text, offset|
                row = { left: [[text, Palette::LANDING_DIM_FG]] }
                next row unless offset.zero?

                row.merge(right: [[pad_left(size_label(book), META_COLUMN), Palette::LANDING_DIM_FG]])
              end
            end

            # Every row of a block ends at the same column: the text stops a
            # clear channel short of the metadata column the sizes right-align
            # into, so no title or author list ever runs alongside a size. A
            # terminal too narrow to afford the channel keeps its text instead.
            def text_column(list)
              available = list.text_width
              return available if available <= MIN_TEXT_WIDTH

              (available - META_COLUMN - META_GAP).clamp(MIN_TEXT_WIDTH, available)
            end

            # Blocks are measured before they are drawn, so each visible book's
            # rows are laid out exactly once per frame.
            def block_lines(list, index, selected)
              @block_lines[index] ||= book_block_rows(@filtered_epubs[index], index == selected, text_column(list))
            end

            # The row a book being opened grows underneath: a slim accent
            # progress stroke with the percentage and message riding after it.
            def render_loading_row(frame, row)
              return if row > frame.body_bottom

              frame.write_line(row, loading_row_segments([frame.content_width / 3, 12].max))
            end

            def loading_row_segments(bar_width)
              filled = (loading_progress.clamp(0.0, 1.0) * bar_width).round
              message = sanitize_text(menu_state_reader&.loading_message)
              [
                ['  ', nil],
                ['━' * filled, accent],
                ['━' * (bar_width - filled), Palette::FAINT_FG],
                ["  #{(loading_progress * 100).round}%", Palette::LANDING_DIM_FG],
                [message.empty? ? '' : " · #{message}", Palette::LANDING_DIM_FG],
              ]
            end

            def render_overflow_scrollbar(list, list_top, height, window)
              blocks_visible = window[:blocks].length
              total = @filtered_epubs.length
              return if blocks_visible.zero? || total <= blocks_visible

              list.render_scrollbar(top: list_top, height: height, total: total,
                                    visible: blocks_visible, offset: window[:start])
            end

            def visible_window(list, height)
              selected = selected_index(@filtered_epubs.length)
              budget = [height - loading_reserve, 1].max
              start = fitting_start(list, selected, budget)
              { start: start, blocks: window_blocks(list, start, selected, budget), selected: selected }
            end

            # A wrapped title makes its block taller than the nominal two rows,
            # which can push the selected book past the fold. Start from the
            # centered guess, then walk the top of the window down until the
            # selected block's last row lands inside the budget.
            def fitting_start(list, selected, budget)
              start = nominal_start(selected, budget)
              rows = (start..selected).sum { |index| block_lines(list, index, selected).length }
              while start < selected && rows > budget
                rows -= block_lines(list, start, selected).length
                start += 1
              end
              start
            end

            def nominal_start(selected, budget)
              capacity = [budget / ROWS_PER_BOOK, 1].max
              return 0 if @filtered_epubs.length <= capacity

              (selected - (capacity / 2)).clamp(0, @filtered_epubs.length - capacity)
            end

            # As many whole blocks as the row budget holds, from +start+ down.
            # The first is taken whatever its height: a book whose title alone
            # outgrows the window still has to be readable.
            def window_blocks(list, start, selected, budget)
              rows_left = budget
              (start...@filtered_epubs.length).each_with_object([]) do |index, blocks|
                lines = block_lines(list, index, selected)
                break blocks if blocks.any? && lines.length > rows_left

                rows_left -= lines.length
                blocks << { index: index, book: @filtered_epubs[index], lines: lines }
              end
            end

            def loading_reserve
              menu_state_reader&.loading_active? ? 1 : 0
            end

            def hint_text
              'ENTER open · / search · wheel scrolls · ESC back'
            end

            # ----- data helpers -----

            def filter_books
              @filtered_epubs = apply_search_filter(@catalog.entries || [], menu_state_reader&.search_query)
            end

            def apply_search_filter(books, query)
              q = query.to_s.strip.downcase
              return books if q.empty?

              books.select do |book|
                name = book['name']&.downcase
                author = book['author']&.downcase
                name&.include?(q) || author&.include?(q)
              end
            end

            def book_title(book)
              meta = safe_metadata_for(book)
              raw = meta_value(meta, :title) || book['name'] || 'Unknown'
              sanitized = sanitize_text(raw)
              sanitized.empty? ? 'Unknown' : sanitized
            end

            def book_author(book)
              value = meta_value(safe_metadata_for(book), :author) ||
                      meta_value(safe_metadata_for(book), :authors) || book['author']
              normalize_author(value)
            end

            def normalize_author(value)
              if value.is_a?(Array)
                value.filter_map do |item|
                  sanitized = sanitize_text(item)
                  sanitized unless sanitized.empty?
                end.join(', ')
              else
                sanitize_text(value)
              end
            end

            def safe_metadata_for(book)
              @catalog.display_metadata_for(
                book['path'],
                size: book['size'],
                modified: book['modified']
              )
            rescue Shoko::MalformedMetadataInputError
              UNREADABLE_METADATA
            end

            def meta_value(meta, key)
              return nil unless meta.is_a?(Hash)

              meta[key]
            end

            def file_format(path)
              extension = File.extname(path.to_s).delete('.').upcase
              extension.empty? ? 'BOOK' : extension
            end

            def size_label(book)
              bytes = book['size'] || @catalog.size_for(book['path'])
              format('%.1f MB', bytes.to_f / (1024 * 1024))
            end

            def sanitize_text(value)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                value.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).strip
            end

            def selected_index(total)
              return 0 if total <= 0

              current = (menu_state_reader&.browse_selected || 0).to_i
              current.clamp(0, total - 1)
            end

            def loading_for?(book)
              menu_state_reader&.loading_active? && menu_state_reader&.loading_path == book['path']
            end

            def loading_progress
              (menu_state_reader&.loading_progress || 0.0).to_f
            end

            attr_reader :menu_state_reader, :menu_session_mutator
          end
        end
      end
    end
  end
end
