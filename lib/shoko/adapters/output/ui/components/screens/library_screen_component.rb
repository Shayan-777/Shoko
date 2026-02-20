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
        include Ui::TextUtils

        Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path,
                          keyword_init: true)
        ItemRenderCtx = Struct.new(:row, :width, :book, :index, :selected, keyword_init: true)

        TIME_INTERVALS = [
          { max: 60, div: 60, singular: 'a minute ago', plural: '%d minutes ago' },
          { max: 3600, div: 3600, singular: 'an hour ago', plural: '%d hours ago' },
          { max: 86_400, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
          { max: 604_800, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
          { max: Float::INFINITY, div: 604_800, singular: 'a week ago', plural: '%d weeks ago' },
        ].freeze

        def initialize(observer_registry, dependencies)
          super(dependencies)
          @observer_registry = observer_registry
          @dependencies = dependencies
          @catalog = dependencies&.catalog_service
          @items = nil
          @menu_state_reader = nil
          # Observe selection changes to support scrolling
          @observer_registry.add_observer(self, %i[menu browse_selected])
        end

        def state_changed(_path, _old, _new)
          invalidate
        end

        def do_render(surface, bounds)
          items = load_items
          selected = menu_state_reader&.browse_selected || 0

          render_header(surface, bounds)

          if items.empty?
            render_empty(surface, bounds)
          else
            render_library(surface, bounds, items, selected)
          end

          render_footer(surface, bounds)
        end

        private

        def menu_state_reader
          @menu_state_reader ||= @dependencies&.menu_state_reader
        end

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
          entry[key] || entry[key.to_s]
        end

        def render_header(surface, bounds)
          write_header(surface, bounds, "#{Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_ACCENT} Library (Cached)#{Terminal::ANSI::RESET}")
        end

        def render_empty(surface, bounds)
          write_empty_message(surface, bounds,
                              "#{Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_DIM}No cached books yet#{Terminal::ANSI::RESET}")
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
          start_index, visible_items = Ui::ListHelpers.slice_visible(items, items_per_page, selected)

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
          divider_line = Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET
          surface.write(bounds, row + 1, 1, divider_line)
        end

        def render_library_item(surface, bounds, ctx)
          is_selected = (ctx.index == ctx.selected)
          dims = compute_column_widths(ctx.width)
          line = format_library_columns(ctx.book, dims)
          pointer = is_selected ? '▸ ' : '  '
          style = library_item_style(is_selected)
          surface.write(bounds, ctx.row, 1, style + pointer + line + Terminal::ANSI::RESET)
        end

        def format_library_columns(book, dims)
          [
            padded_column((book.title || 'Unknown').to_s, dims[:title_w]),
            padded_column((book.authors || '').to_s, dims[:author_w]),
            pad_right((book.year || '').to_s[0, 4], dims[:year_w]),
            padded_column(relative_accessed_label(book.last_accessed), dims[:last_w]),
            pad_left(format_size(book.size_bytes), dims[:size_w]),
          ].join(' ' * dims[:gap])
        end

        def padded_column(text, width)
          pad_right(truncate_text(text, width), width)
        end

        def library_item_style(is_selected)
          if is_selected
            Adapters::Output::Ui::Constants::Ui::SELECTION_HIGHLIGHT
          else
            Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_PRIMARY
          end
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

          seconds = time_elapsed_seconds(iso)
          return '' unless seconds

          format_relative_time(seconds)
        end

        def time_elapsed_seconds(iso)
          t = Time.parse(iso)
          (Time.now - t).to_i
        rescue StandardError
          nil
        end

        def format_relative_time(seconds)
          return 'a minute ago' if seconds < 60

          interval = TIME_INTERVALS.find { |i| seconds < i[:max] }
          value = seconds / interval[:div]
          value == 1 ? interval[:singular] : format(interval[:plural], value)
        end

        def render_footer(surface, bounds)
          write_footer(surface, bounds,
                       "#{Adapters::Output::Ui::Constants::Ui::COLOR_TEXT_DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}")
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
