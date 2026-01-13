# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # LibraryScreenComponent renders the cached library view with
      # sortable columns and paging of visible items.
      class LibraryScreenComponent < BaseScreenComponent
        include UI::TextUtils

        Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path,
                          keyword_init: true)
        ItemRenderCtx = Struct.new(:row, :width, :book, :index, :selected, keyword_init: true)

        def initialize(state, dependencies)
          super(dependencies)
          @state = state
          @catalog = dependencies.resolve(:catalog_service)
          @items = nil
          # Observe selection changes to support scrolling
          @state.add_observer(self, %i[menu browse_selected])
        end

        def state_changed(_path, _old, _new)
          invalidate
        end

        def do_render(surface, bounds)
          items = load_items
          selected = Shoko::Application::Selectors::MenuSelectors.browse_selected(@state) || 0

          render_header(surface, bounds)

          if items.empty?
            render_empty(surface, bounds)
          else
            render_library(surface, bounds, items, selected)
          end

          render_footer(surface, bounds)
        end

        private

        def load_items
          return @items if @items

          entries = Array(@catalog.cached_library_entries)
          @items = entries.map do |entry|
            Item.new(
              title: entry[:title] || entry['title'],
              authors: entry[:authors] || entry['authors'],
              year: entry[:year] || entry['year'],
              last_accessed: entry[:last_accessed] || entry['last_accessed'],
              size_bytes: entry[:size_bytes] || entry['size_bytes'] || @catalog.size_for(entry[:open_path] || entry['open_path']),
              open_path: entry[:open_path] || entry['open_path'],
              epub_path: entry[:epub_path] || entry['epub_path']
            )
          end
        end

        def render_header(surface, bounds)
          write_header(surface, bounds, "#{Adapters::Output::Ui::Constants::UI::COLOR_TEXT_ACCENT} Library (Cached)#{Terminal::ANSI::RESET}")
        end

        def render_empty(surface, bounds)
          write_empty_message(surface, bounds, "#{Adapters::Output::Ui::Constants::UI::COLOR_TEXT_DIM}No cached books yet#{Terminal::ANSI::RESET}")
        end

        def render_library(surface, bounds, items, selected)
          list_start = 4
          width = bounds.width
          height = bounds.height
          list_height = height - list_start - 2
          return if list_height <= 0

          draw_list_header(surface, bounds, width, list_start)
          list_start += 2
          list_height -= 2

          items_per_page = list_height
          start_index, visible_items = UI::ListHelpers.slice_visible(items, items_per_page, selected)

          current_row = list_start
          visible_items.each_with_index do |book, i|
            break if current_row >= height - 1

            ctx = ItemRenderCtx.new(row: current_row, width: width, book: book,
                                    index: start_index + i, selected: selected)
            render_library_item(surface, bounds, ctx)
            current_row += 1
          end
        end

        def draw_list_header(surface, bounds, width, row)
          dims = compute_column_widths(width)

          headers = [
            pad_right('Title', dims[:title_w]),
            pad_right('Author(s)', dims[:author_w]),
            pad_right('Year', dims[:year_w]),
            pad_right('Last accessed', dims[:last_w]),
            pad_left('Size', dims[:size_w]),
          ].join(' ' * dims[:gap])
          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::DEFAULT_FG
          header_line = header_style + (' ' * dims[:pointer_w]) + headers + Terminal::ANSI::RESET
          surface.write(bounds, row, 1, header_line)
          divider = '─' * [width - 2, 1].max
          divider_line = Adapters::Output::Ui::Constants::UI::COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET
          surface.write(bounds, row + 1, 1, divider_line)
        end

        def render_library_item(surface, bounds, ctx)
          is_selected = (ctx.index == ctx.selected)
          dims = compute_column_widths(ctx.width)

          pointer = is_selected ? '▸ ' : '  '
          book = ctx.book
          t_w = dims[:title_w]
          a_w = dims[:author_w]
          y_w = dims[:year_w]
          l_w = dims[:last_w]
          s_w = dims[:size_w]
          title_col = pad_right(truncate_text((book.title || 'Unknown').to_s, t_w), t_w)
          author_col = pad_right(truncate_text((book.authors || '').to_s, a_w), a_w)
          year_col = pad_right((book.year || '').to_s[0, 4], y_w)
          last_col = pad_right(truncate_text(relative_accessed_label(book.last_accessed), l_w), l_w)
          size_col = pad_left(format_size(book.size_bytes), s_w)

          line = [title_col, author_col, year_col, last_col, size_col].join(' ' * dims[:gap])
          style = is_selected ? Adapters::Output::Ui::Constants::UI::SELECTION_HIGHLIGHT : Adapters::Output::Ui::Constants::UI::COLOR_TEXT_PRIMARY
          surface.write(bounds, ctx.row, 1, style + pointer + line + Terminal::ANSI::RESET)
        end

        def compute_column_widths(total_width)
          pointer_w = 2
          gap = 2
          remaining = total_width - pointer_w - (gap * 4)
          year_w = 6
          last_w = 16
          size_w = 8
          author_w = [(remaining * 0.25).to_i, 12].max.clamp(12, remaining - 20 - year_w - last_w - size_w)
          title_w = [remaining - author_w - year_w - last_w - size_w, 20].max
          { pointer_w: pointer_w, gap: gap, title_w: title_w, author_w: author_w,
            year_w: year_w, last_w: last_w, size_w: size_w }
        end

        def format_size(bytes)
          mb = (bytes.to_f / (1024 * 1024)).round(1)
          format('%.1f MB', mb)
        end

        def relative_accessed_label(iso)
          return '' unless iso

          t = begin
            Time.parse(iso)
          rescue StandardError
            nil
          end
          return '' unless t

          seconds = (Time.now - t).to_i
          minutes = seconds / 60
          hours = seconds / 3600
          days = seconds / 86_400
          weeks = days / 7

          if hours < 1
            minutes <= 1 ? 'a minute ago' : "#{minutes} minutes ago"
          elsif days < 1
            hours == 1 ? 'an hour ago' : "#{hours} hours ago"
          elsif days == 1
            'yesterday'
          elsif days < 7
            "#{days} days ago"
          else
            weeks == 1 ? 'a week ago' : "#{weeks} weeks ago"
          end
        end

        def render_footer(surface, bounds)
          write_footer(surface, bounds,
                       "#{Adapters::Output::Ui::Constants::UI::COLOR_TEXT_DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}")
        end

        public

        # Public accessor for items to avoid reflective access from MainMenu
        def items
          load_items
        end

        def invalidate_cache!
          @items = nil
        end
      end
    end
  end
end
