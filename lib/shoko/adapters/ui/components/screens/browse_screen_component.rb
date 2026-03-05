# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Browse screen component that renders the book browsing interface
          class BrowseScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            BookItemCtx = Struct.new(:row, :book, :selected, :layout)

            def initialize(catalog_service, observer_registry, dependencies = nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @filtered_epubs = []
              @menu_state_reader = nil
              @menu_state_writer = nil

              # Observe state changes for search and selection
              @observer_registry.add_observer(self, %i[menu browse_selected], %i[menu search_query],
                                              %i[menu search_active])
            end

            def state_changed(path, _old_value, _new_value)
              case path
              when %i[menu search_query]
                filter_books
              end
            end

            def filtered_epubs=(books)
              @filtered_epubs = apply_search_filter(books || [], menu_state_reader&.search_query)
            end

            def selected
              menu_state_reader&.browse_selected
            end

            def navigate(key)
              return unless @filtered_epubs.any?

              current = menu_state_reader&.browse_selected || 0
              max_index = @filtered_epubs.length - 1

              new_selected = case key
                             when :up then [current - 1, 0].max
                             when :down then [current + 1, max_index].min
                             else current
                             end

              menu_state_writer&.update_browse_selected(new_selected)
            end

            def selected_book
              browse_selected = menu_state_reader&.browse_selected || 0
              @filtered_epubs[browse_selected]
            end

            # Expose filtered list count for navigation logic integration
            def filtered_count
              (@filtered_epubs || []).length
            end

            # Expose random access by index (read-only)
            def book_at(index)
              (@filtered_epubs || [])[index]
            end

            def do_render(surface, bounds)
              @filtered_epubs ||= []
              layout = layout_metrics(bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Browse Library')
              frame.render_divider

              render_search(surface, bounds, layout)
              render_status(surface, bounds, layout)

              if @filtered_epubs.nil? || @filtered_epubs.empty?
                render_empty_state(surface, bounds, layout)
              else
                render_books_list(surface, bounds, layout)
              end

              render_footer(bounds, layout, frame: frame)
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

            def render_status(surface, bounds, layout)
              total = @filtered_epubs&.length.to_i
              status = @catalog.scan_status
              message = Shoko::Shared::Terminal::TextSanitizer.sanitize(@catalog.scan_message.to_s,
                                                                        preserve_newlines: false,
                                                                        preserve_tabs: false)
              status_row = layout[:status_row]
              count_text = "Found #{total} #{total == 1 ? 'book' : 'books'}"

              status_text = ''
              status_color = COLOR_TEXT_DIM
              if status
                status_text = case status
                              when :scanning then "⟳ #{message}"
                              when :error    then "✗ #{message}"
                              when :done     then "✓ #{message}"
                              else ''
                              end
                status_color = case status
                               when :scanning then COLOR_TEXT_WARNING
                               when :error then COLOR_TEXT_ERROR
                               when :done then COLOR_TEXT_SUCCESS
                               else COLOR_TEXT_DIM
                               end
              end
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: status_row,
                indent: layout[:indent],
                left: count_text,
                right: status_text,
                width: layout[:content_width],
                left_color: COLOR_TEXT_DIM,
                right_color: status_color
              )
            end

            def render_empty_state(surface, bounds, layout)
              status = @catalog.scan_status
              empty_text = if status == :scanning
                             "#{COLOR_TEXT_WARNING}⟳ Scanning for books...#{Shoko::Shared::Terminal::Ansi::RESET}"
                           else
                             "#{COLOR_TEXT_DIM}No matching books#{Shoko::Shared::Terminal::Ansi::RESET}"
                           end
              row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
              surface.write(bounds, row, layout[:indent], empty_text)
            end

            def render_books_list(surface, bounds, layout)
              list_start_row = layout[:list_start_row]
              list_height = bounds.height - list_start_row - 2
              return if list_height <= 0

              selected = menu_state_reader&.browse_selected || 0
              start_index, visible_books = Ui::ListHelpers.slice_visible(@filtered_epubs, list_height, selected)

              draw_list_header(surface, bounds, layout, layout[:header_row])
              current_row = list_start_row

              loading_path = menu_state_reader&.loading_path
              loading_active = menu_state_reader&.loading_active?
              loading_progress = (menu_state_reader&.loading_progress || 0.0).to_f
              loading_message = menu_state_reader&.loading_message

              visible_books.each_with_index do |book, index|
                is_selected = (start_index + index) == selected
                ctx = BookItemCtx.new(row: current_row, book: book, selected: is_selected, layout: layout)
                render_book_item(surface, bounds, ctx)

                progress_row = current_row + 1
                if loading_active && loading_path == book['path'] && progress_row <= bounds.bottom
                  rows_used = draw_inline_progress(surface, bounds, layout, progress_row, loading_progress,
loading_message)
                  current_row += 1 + rows_used
                else
                  current_row += 1
                end
              end
            end

            def render_book_item(surface, bounds, ctx)
              cols = ctx.layout[:columns]
              path = ctx.book['path']
              meta = safe_metadata_for(path)
              title = display_title(meta_title: meta[:title], fallback_name: ctx.book['name'])
              size_mb = format_size(ctx.book['size'] || @catalog.size_for(path))
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: ctx.row,
                indent: ctx.layout[:indent],
                cells: [
                  pad_right(truncate_text(title, cols[:title]), cols[:title]),
                  pad_left(size_mb, cols[:size]),
                ],
                widths: [cols[:title], cols[:size]],
                selected: ctx.selected
              )
            end

            def format_browse_columns(book, layout)
              path = book['path']
              meta = safe_metadata_for(path)
              title = display_title(meta_title: meta[:title], fallback_name: book['name'])
              size_mb = format_size(book['size'] || @catalog.size_for(path))

              cols = layout[:columns]
              gap = ' ' * layout[:gap]
              [
                pad_right(truncate_text(title, cols[:title]), cols[:title]),
                pad_left(size_mb, cols[:size]),
              ].join(gap)
            end

            def safe_metadata_for(path)
              @catalog.metadata_for(path)
            rescue Shoko::MalformedMetadataInputError
              metadata_fallback
            end

            def display_title(meta_title:, fallback_name:)
              raw = meta_title || fallback_name || 'Unknown'
              sanitized = Shoko::Shared::Terminal::TextSanitizer.sanitize(
                raw.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).strip
              sanitized.empty? ? 'Unknown' : sanitized
            end

            def metadata_fallback
              {}
            end

            def draw_list_header(surface, bounds, layout, row)
              return if row < 5

              cols = layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: row,
                indent: layout[:indent],
                headers: ['Title', 'Size'],
                widths: [cols[:title], cols[:size]],
                divider_char: '─'
              )
            end

            def format_size(bytes)
              mb = (bytes.to_f / (1024 * 1024)).round(1)
              format('%.1f MB', mb)
            end

            def draw_inline_progress(surface, bounds, layout, row, progress, message)
              return 0 if row > bounds.bottom

              rows_used = 0
              indent = layout[:indent]
              content_width = layout[:content_width]
              message_text = message.to_s.strip

              unless message_text.empty?
                truncated = Shoko::Shared::Terminal::TextMetrics.truncate_to(message_text, content_width)
                surface.write(bounds, row, indent, "#{COLOR_TEXT_DIM}#{truncated}#{Shoko::Shared::Terminal::Ansi::RESET}")
                rows_used += 1
                row += 1
                return rows_used if row > bounds.bottom
              end

              bar_col = layout[:indent]
              MenuDesign::ProgressRenderer.new(surface, bounds).render(
                row: row,
                indent: bar_col,
                width: layout[:content_width],
                progress: progress,
                filled_char: '━',
                empty_char: '━'
              )
              rows_used + 1
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search',
                query: (menu_state_reader&.search_query || ''),
                cursor: menu_state_reader&.search_cursor,
                row: layout[:search_row],
                indent: layout[:indent],
                width: layout[:content_width],
                active: !menu_state_reader&.search_active?.nil?
              )
            end

            def render_footer(bounds, layout, frame:)
              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(footer_text, layout[:content_width])
              frame.render_footer(text: clipped, row: bounds.height - 1, indent: layout[:indent])
            end

            def layout_metrics(bounds)
              height = bounds.height
              width  = bounds.width
              row_base = height / 6

              base_width = [width - 8, 72].min
              column_spec = column_layout(base_width)
              content_width = column_spec[:content_width]
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)

              {
                indent: indent,
                content_width: content_width,
                columns: column_spec[:columns],
                gap: column_spec[:gap],
                search_row: [row_base, 3].max,
                status_row: [row_base + 2, 4].max,
                header_row: [row_base + 4, 6].max,
                list_start_row: [row_base + 6, 8].max,
              }
            end

            def footer_text
              total = @filtered_epubs&.length.to_i
              query = Shoko::Shared::Terminal::TextSanitizer.sanitize(
                menu_state_reader&.search_query.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).strip
              return "#{total} #{total == 1 ? 'book' : 'books'}" if query.empty?

              "Filter: #{query}"
            end

            def column_layout(content_width)
              gap = 4
              size_w = 8
              title_w = [content_width - size_w - gap, 24].max
              content_width = title_w + size_w + gap

              {
                content_width: content_width,
                columns: {
                  title: title_w,
                  size: size_w,
                },
                gap: gap,
              }
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def menu_state_writer
              @menu_state_writer ||= @dependencies&.menu_state_writer
            end

            # truncate_text provided by Ui::TextUtils
          end
        end
      end
    end
  end
end
