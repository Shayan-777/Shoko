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
          # the menu-side sibling of the in-book search list: roomy two-row
          # blocks (title, then author · format · size) with the family's
          # selection strip, a slim scrollbar when the shelf overflows, and
          # the search input living in the status bar exactly like in-book
          # search. A book being opened grows a progress row under its block.
          class BrowseScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette

            ROWS_PER_BOOK = 2
            UNREADABLE_METADATA = Object.new.freeze

            attr_reader :filtered_epubs

            def initialize(catalog_service, observer_registry, dependencies = nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @filtered_epubs = []
              @menu_state_reader = nil
              @menu_session_mutator = nil

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
              @dependencies.respond_to?(:menu_hit_registry) ? @dependencies.menu_hit_registry : nil
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
              window = visible_window(height)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :browse })
              render_block_window(list, frame, window, top)
              render_overflow_scrollbar(list, top, height, window)
            end

            def render_block_window(list, frame, window, top)
              row = top
              window[:books].each_with_index do |book, offset|
                index = window[:start] + offset
                rows = book_block_rows(book, index == window[:selected])
                break if row + rows.length - 1 > frame.body_bottom

                render_book_block(list, frame, book: book, index: index, row: row,
                                               selected: index == window[:selected], rows: rows)
                row += rows.length + (loading_for?(book) ? 1 : 0)
              end
            end

            def render_book_block(list, frame, book:, index:, row:, selected:, rows:)
              list.block(row: row, lines: rows, selected: selected,
                         action: { type: :list_row, list: :browse, index: index })
              render_loading_row(frame, row + ROWS_PER_BOOK) if loading_for?(book)
            end

            # Rows for one book: bright title, then a dim author · format · size
            # line — the in-book search block shape, retold for the shelf.
            def book_block_rows(book, selected)
              title_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              [
                { left: [[book_title(book), title_fg]] },
                { left: [["#{book_author(book)}#{' · ' unless book_author(book).empty?}#{file_format(book['path'])}",
                          Palette::LANDING_DIM_FG]],
                  right: [[size_label(book), Palette::LANDING_DIM_FG]] },
              ]
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
              blocks_visible = window[:capacity]
              total = @filtered_epubs.length
              return if total <= blocks_visible

              list.render_scrollbar(top: list_top, height: height, total: total,
                                    visible: blocks_visible, offset: window[:start])
            end

            def visible_window(height)
              selected = selected_index(@filtered_epubs.length)
              capacity = [(height - loading_reserve) / ROWS_PER_BOOK, 1].max
              start = window_start(selected, capacity)
              {
                start: start,
                books: @filtered_epubs[start, capacity] || [],
                selected: selected,
                capacity: capacity,
              }
            end

            def window_start(selected, capacity)
              return 0 if @filtered_epubs.length <= capacity

              (selected - (capacity / 2)).clamp(0, @filtered_epubs.length - capacity)
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

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def menu_session_mutator
              @menu_session_mutator ||= @dependencies&.menu_session_mutator
            end
          end
        end
      end
    end
  end
end
