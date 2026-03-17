# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Browse screen component that renders the searchable library list
          # with a persistent inspector for the selected item.
          class BrowseScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            BookItemCtx = Struct.new(:row, :book, :selected, :columns, :indent)
            DETAIL_KEY_WIDTH = 7
            BROWSE_PREFERRED_WIDTH = 132
            UNREADABLE_METADATA = Object.new.freeze

            def initialize(catalog_service, observer_registry, dependencies = nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @filtered_epubs = []
              @menu_state_reader = nil
              @menu_session_mutator = nil

              @observer_registry.add_observer(self, %i[menu browse_selected], %i[menu search_query],
                                              %i[menu search_active])
            end

            def state_changed(path, _old_value, _new_value)
              filter_books if path == %i[menu search_query]
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
              menu_session_mutator&.update_browse_selected(new_selected)
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
              shell = MenuDesign::MasterDetailShell.new(surface, bounds)
              layout = shell.build_layout(
                prelude_rows: 1,
                detail_visible: true,
                desired_detail_width: 40,
                min_primary_width: 38,
                min_detail_width: 30,
                stacked_detail_height: 8,
                preferred_width: BROWSE_PREFERRED_WIDTH
              )
              count_text, status_text, status_color = summary_payload

              shell.render_frame(
                layout: layout,
                title: 'Browse Library',
                hint: 'ENTER open  / search  ESC back',
                summary_left: count_text,
                summary_right: status_text,
                footer: footer_text,
                summary_right_color: status_color
              )
              render_search(surface, bounds, layout)
              shell.render_panels(layout: layout, primary_title: 'Results', secondary_title: 'Selection')

              if @filtered_epubs.empty?
                render_empty_results(surface, bounds, layout.primary_panel.content)
              else
                render_books_list(surface, bounds, layout.primary_panel.content)
              end

              render_selection_details(surface, bounds, layout.secondary_panel&.content)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

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

            def summary_payload
              total = @filtered_epubs.length
              count_text = "Found #{total} #{total == 1 ? 'book' : 'books'}"
              status = @catalog.scan_status
              message = sanitize_text(@catalog.scan_message)
              case status
              when :scanning
                [count_text, message.empty? ? 'Scanning library' : "Scanning: #{message}", COLOR_TEXT_WARNING]
              when :error
                [count_text, message.empty? ? 'Scan failed' : message, COLOR_TEXT_ERROR]
              when :done
                [count_text, message.empty? ? 'Library ready' : message, COLOR_TEXT_DIM]
              else
                [count_text, '', COLOR_TEXT_DIM]
              end
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search',
                query: menu_state_reader&.search_query || '',
                cursor: menu_state_reader&.search_cursor,
                row: layout.prelude_top,
                indent: layout.shell_indent,
                width: layout.shell_width,
                active: menu_state_reader&.search_active? == true,
                compact: true
              )
            end

            def render_books_list(surface, bounds, panel)
              columns = column_layout(panel.width)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: ['Title', 'Size'],
                widths: [columns[:title], columns[:size]],
                divider_char: '─'
              )

              visible_rows = [panel.height - 2, 0].max
              return if visible_rows <= 0

              selected = selected_index(@filtered_epubs.length)
              start_index, visible_books = Ui::ListHelpers.slice_visible(@filtered_epubs, visible_rows, selected)
              current_row = panel.y + 2
              visible_books.each_with_index do |book, offset|
                break if current_row > panel.bottom

                absolute_index = start_index + offset
                ctx = BookItemCtx.new(
                  row: current_row,
                  book: book,
                  selected: absolute_index == selected,
                  columns: columns,
                  indent: panel.x
                )
                render_book_item(surface, bounds, ctx)

                progress_row = current_row + 1
                if loading_for?(book) && progress_row <= panel.bottom
                  rows_used = draw_inline_progress(
                    surface,
                    bounds,
                    panel,
                    progress_row,
                    loading_progress,
                    loading_message
                  )
                  current_row += 1 + rows_used
                else
                  current_row += 1
                end
              end
            end

            def render_book_item(surface, bounds, ctx)
              path = ctx.book['path']
              meta = safe_metadata_for(path)
              title = display_title(meta_title: meta_value(meta, :title), fallback_name: ctx.book['name'])
              size_mb = format_size(ctx.book['size'] || @catalog.size_for(path))
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: ctx.row,
                indent: ctx.indent,
                cells: [
                  pad_right(truncate_text(title, ctx.columns[:title]), ctx.columns[:title]),
                  pad_left(size_mb, ctx.columns[:size]),
                ],
                widths: [ctx.columns[:title], ctx.columns[:size]],
                selected: ctx.selected
              )
            end

            def render_empty_results(surface, bounds, panel)
              status = @catalog.scan_status
              message = status == :scanning ? 'Scanning for books...' : 'No matching books'
              row = panel.y + ([panel.height / 2, 0].max)
              surface.write(bounds, row, panel.x, "#{COLOR_TEXT_DIM}#{message}#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def render_selection_details(surface, bounds, panel)
              return unless panel

              book = selected_book
              unless book
                surface.write(bounds, panel.y, panel.x,
                              "#{COLOR_TEXT_DIM}No book selected#{Shoko::Shared::Terminal::Ansi::RESET}")
                return
              end

              row = panel.y
              path = book['path']
              meta = safe_metadata_for(path)
              title = display_title(meta_title: meta_value(meta, :title), fallback_name: book['name'])
              title_lines = wrap_text(title, panel.width)
              title_style = "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}"
              title_lines.each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, "#{title_style}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end

              author = display_author(meta, book)
              if author.empty? || row > panel.bottom
                row += 1
              else
                surface.write(bounds, row, panel.x, "#{COLOR_TEXT_DIM}#{author}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 2
              end

              detail_lines(book, panel.width).each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, "#{COLOR_TEXT_PRIMARY}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
            end

            def detail_lines(book, width)
              lines = []
              append_detail(lines, 'Size', format_size(book['size'] || @catalog.size_for(book['path'])), width)
              append_detail(lines, 'Format', file_format(book['path']), width)
              append_detail(lines, 'File', File.basename(book['path'].to_s), width)

              lines << ''
              lines << "#{COLOR_TEXT_DIM}Enter opens the selected book#{Shoko::Shared::Terminal::Ansi::RESET}"
              lines
            end

            def append_detail(lines, label, value, width)
              safe_value = sanitize_text(value)
              safe_value = '—' if safe_value.empty?
              value_width = [width - DETAIL_KEY_WIDTH - 1, 8].max
              wrap_text(safe_value, value_width).each_with_index do |part, index|
                key = index.zero? ? pad_right("#{label}:", DETAIL_KEY_WIDTH) : ' ' * DETAIL_KEY_WIDTH
                lines << "#{key}#{truncate_text(part, value_width)}"
              end
            end

            def display_author(meta, book)
              normalize_author(meta_value(meta, :author) || meta_value(meta, :authors) || book['author'])
            end

            def safe_metadata_for(path)
              @catalog.metadata_for(path)
            rescue Shoko::MalformedMetadataInputError
              UNREADABLE_METADATA
            end

            def meta_value(meta, key)
              return nil unless meta.is_a?(Hash)

              meta[key]
            end

            def normalize_author(value)
              if value.is_a?(Array)
                names = value.filter_map do |item|
                  sanitized = sanitize_text(item)
                  sanitized unless sanitized.empty?
                end
                names.join(', ')
              else
                sanitize_text(value)
              end
            end

            def display_title(meta_title:, fallback_name:)
              raw = meta_title || fallback_name || 'Unknown'
              sanitized = sanitize_text(raw)
              sanitized.empty? ? 'Unknown' : sanitized
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

            def loading_message
              menu_state_reader&.loading_message.to_s
            end

            def draw_inline_progress(surface, bounds, panel, row, progress, message)
              return 0 if row > panel.bottom

              rows_used = 0
              message_text = sanitize_text(message)
              unless message_text.empty?
                truncated = Shoko::Shared::Terminal::TextMetrics.truncate_to(message_text, panel.width)
                surface.write(bounds, row, panel.x, "#{COLOR_TEXT_DIM}#{truncated}#{Shoko::Shared::Terminal::Ansi::RESET}")
                rows_used += 1
                row += 1
                return rows_used if row > panel.bottom
              end

              MenuDesign::ProgressRenderer.new(surface, bounds).render(
                row: row,
                indent: panel.x,
                width: panel.width,
                progress: progress,
                filled_char: '━',
                empty_char: '━'
              )
              rows_used + 1
            end

            def footer_text
              total = @filtered_epubs.length
              query = sanitize_text(menu_state_reader&.search_query)
              return "#{total} #{total == 1 ? 'book' : 'books'}" if query.empty?

              "Filter: #{query}"
            end

            def column_layout(content_width)
              gap = 3
              size_width = 9
              title_width = [content_width - size_width - gap, 16].max
              { title: title_width, size: size_width }
            end

            def file_format(path)
              extension = File.extname(path.to_s).delete('.').upcase
              extension.empty? ? 'BOOK' : extension
            end

            def format_size(bytes)
              mb = (bytes.to_f / (1024 * 1024)).round(1)
              format('%.1f MB', mb)
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
