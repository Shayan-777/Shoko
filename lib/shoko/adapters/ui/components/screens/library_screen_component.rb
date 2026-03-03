# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/layout'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative '../../../../shared/terminal/ansi'
require_relative '../../../../shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # LibraryScreenComponent renders cached books as a clean title list
          # with an optional details drawer toggled via space.
          class LibraryScreenComponent < BaseScreenComponent
            include Ui::TextUtils

            Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path,
                              keyword_init: true)

            TIME_INTERVALS = [
              { max: 3600, div: 60, singular: 'a minute ago', plural: '%d minutes ago' },
              { max: 86_400, div: 3600, singular: 'an hour ago', plural: '%d hours ago' },
              { max: 604_800, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
              { max: Float::INFINITY, div: 604_800, singular: 'a week ago', plural: '%d weeks ago' },
            ].freeze

            SPLIT_DETAILS_MIN_WIDTH = 92
            DETAILS_PANEL_MIN_WIDTH = 34
            DETAILS_PANEL_MAX_WIDTH = 44
            DETAILS_PANEL_STACK_HEIGHT = 8
            DETAILS_PANEL_GAP = 3

            def initialize(observer_registry, dependencies, menu_visual_profile: nil)
              super(dependencies)
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @catalog = dependencies&.catalog_service
              @items = nil
              @menu_state_reader = nil
              @observer_registry.add_observer(self, %i[menu browse_selected], %i[menu library_details_open])
            end

            def state_changed(_path, _old, _new)
              invalidate
            end

            def do_render(surface, bounds)
              items = load_items
              selected = selected_index(items.length)
              details_open = details_open?

              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Library (Cached)', hint: header_hint(details_open, items.empty?))
              frame.render_divider

              if items.empty?
                render_empty(surface, bounds)
              else
                render_library(surface, bounds, items, selected, details_open)
              end

              frame.render_footer(text: footer_text(items.length, details_open))
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

            def selected_index(total)
              current = (menu_state_reader&.browse_selected || 0).to_i
              return 0 if total <= 0

              current.clamp(0, total - 1)
            end

            def details_open?
              reader = menu_state_reader
              return false unless reader

              !!reader.library_details_open?
            rescue Shoko::Error
              false
            end

            def header_hint(details_open, empty)
              return 'ESC back' if empty

              details_label = details_open ? 'SPACE hide details' : 'SPACE show details'
              "#{details_label}  ENTER open  ESC back"
            end

            def footer_text(count, details_open)
              noun = count == 1 ? 'book' : 'books'
              if details_open
                "#{count} cached #{noun} • details panel open"
              else
                "#{count} cached #{noun}"
              end
            end

            def render_empty(surface, bounds)
              row = bounds.height / 2
              MenuDesign::StatusRenderer.new(surface, bounds).render_empty(
                row: row,
                indent: 2,
                message: 'No cached books yet',
                color: Adapters::Ui::Constants::Ui::COLOR_TEXT_DIM
              )
            end

            def render_library(surface, bounds, items, selected, details_open)
              layout = compute_layout(bounds, details_open)
              render_controls_row(surface, bounds, layout, details_open)
              render_titles(surface, bounds, layout, items, selected)
              render_details_panel(surface, bounds, layout, items[selected], selected, items.length)
            end

            def render_controls_row(surface, bounds, layout, details_open)
              hint = details_open ? 'SPACE hide metadata' : 'SPACE inspect metadata'
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:controls_row],
                indent: layout[:list_indent],
                left: 'J/K move',
                right: hint,
                width: layout[:list_render_width],
                left_color: Adapters::Ui::Constants::Ui::COLOR_TEXT_DIM,
                right_color: Adapters::Ui::Constants::Ui::COLOR_TEXT_DIM
              )
            end

            def render_titles(surface, bounds, layout, items, selected)
              draw_titles_header(surface, bounds, layout)
              start_index, visible = Ui::ListHelpers.slice_visible(items, layout[:list_height], selected)

              current_row = layout[:list_start_row]
              visible.each_with_index do |book, offset|
                break if current_row > layout[:list_bottom_row]

                abs_index = start_index + offset
                title = safe_text((book.title || 'Untitled').to_s)
                decorated = "#{pad_left((abs_index + 1).to_s, 3)}  #{title}"
                cells = [pad_right(truncate_text(decorated, layout[:title_col_width]), layout[:title_col_width])]

                MenuDesign::TableRenderer.new(surface, bounds).render_row(
                  row: current_row,
                  indent: layout[:list_indent],
                  cells: cells,
                  widths: [layout[:title_col_width]],
                  selected: abs_index == selected
                )
                current_row += 1
              end
            end

            def draw_titles_header(surface, bounds, layout)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: layout[:header_row],
                indent: layout[:list_indent],
                headers: ['Book Titles'],
                widths: [layout[:title_col_width]],
                divider_char: '─'
              )
            end

            def render_details_panel(surface, bounds, layout, item, selected, total)
              panel = layout[:details_panel]
              return unless panel && item

              x = panel[:x]
              y = panel[:y]
              width = panel[:width]
              height = panel[:height]
              return if width < 6 || height < 4

              border_color = Adapters::Ui::Constants::Ui::MENU_DIVIDER_FG
              reset = Shoko::Shared::Terminal::Ansi::RESET

              top = "#{border_color}╭#{'─' * (width - 2)}╮#{reset}"
              bottom = "#{border_color}╰#{'─' * (width - 2)}╯#{reset}"
              surface.write(bounds, y, x, top)
              surface.write(bounds, y + height - 1, x, bottom)

              inner_width = width - 2
              inner_height = height - 2
              lines = details_lines(item, selected, total, inner_width)
              lines = fit_lines(lines, inner_height)

              inner_height.times do |offset|
                text = lines[offset] || ''
                padded = pad_right(text, inner_width)
                surface.write(bounds, y + 1 + offset, x,
                              "#{border_color}│#{reset}#{padded}#{border_color}│#{reset}")
              end
            end

            def details_lines(item, selected, total, inner_width)
              lines = []
              lines << 'DETAILS'
              lines << "Book #{selected + 1} of #{total}"
              lines << ''

              append_detail(lines, 'Title', item.title, inner_width)
              append_detail(lines, 'Authors', item.authors, inner_width)
              append_detail(lines, 'Year', item.year, inner_width)
              append_detail(lines, 'Accessed', relative_accessed_label(item.last_accessed), inner_width)
              append_detail(lines, 'Size', format_size(item.size_bytes), inner_width)
              append_detail(lines, 'Cache', compact_path(item.open_path), inner_width)
              append_detail(lines, 'EPUB', compact_path(item.epub_path), inner_width)
              lines
            end

            def append_detail(lines, label, value, width)
              key_width = [label.to_s.length + 1, 9].max
              value_width = [width - key_width - 1, 8].max
              safe_value = safe_text(value.to_s.strip)
              safe_value = '—' if safe_value.empty?
              wrapped = wrap_text(safe_value, value_width)
              wrapped = ['—'] if wrapped.empty?

              wrapped.each_with_index do |part, index|
                key = index.zero? ? pad_right("#{label}:", key_width) : ' ' * key_width
                lines << "#{key}#{truncate_text(part, value_width)}"
              end
            end

            def fit_lines(lines, max_lines)
              return [] if max_lines <= 0
              return lines.first(max_lines) if lines.length <= max_lines

              clipped = lines.first(max_lines)
              clipped[-1] = truncate_text('…', [clipped[-1].to_s.length, 1].max)
              clipped
            end

            def compact_path(path)
              value = path.to_s
              return '—' if value.empty?

              safe_text(File.basename(value))
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                                         preserve_tabs: false)
            end

            def compute_layout(bounds, details_open)
              content_width = MenuDesign::Layout.centered_content_width(bounds, preferred: 102, min: 46,
                                                                        horizontal_padding: 8)
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)
              header_row = 4
              list_start_row = 6
              controls_row = 3
              content_bottom = bounds.height - 2
              available_rows = [content_bottom - list_start_row + 1, 1].max

              list_width = content_width
              details_panel = nil

              if details_open && content_width >= SPLIT_DETAILS_MIN_WIDTH
                details_width = (content_width * 0.38).to_i
                details_width = details_width.clamp(DETAILS_PANEL_MIN_WIDTH, DETAILS_PANEL_MAX_WIDTH)
                candidate_width = content_width - details_width - DETAILS_PANEL_GAP

                if candidate_width >= 24
                  list_width = candidate_width
                  details_panel = {
                    x: indent + list_width + DETAILS_PANEL_GAP,
                    y: header_row,
                    width: details_width,
                    height: [content_bottom - header_row + 1, 4].max,
                  }
                end
              end

              if details_open && details_panel.nil?
                panel_height = [DETAILS_PANEL_STACK_HEIGHT, available_rows - 3].min
                panel_height = 0 if panel_height < 5

                if panel_height.positive?
                  list_rows = [available_rows - panel_height - 1, 2].max
                  details_panel = {
                    x: indent,
                    y: list_start_row + list_rows + 1,
                    width: content_width,
                    height: panel_height,
                  }
                  available_rows = list_rows
                end
              end

              {
                controls_row: controls_row,
                header_row: header_row,
                list_start_row: list_start_row,
                list_bottom_row: list_start_row + available_rows - 1,
                list_height: [available_rows, 1].max,
                list_indent: indent,
                list_render_width: list_width,
                title_col_width: [list_width - 2, 8].max,
                details_panel: details_panel,
              }
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
            rescue Shoko::Error
              nil
            end

            def format_relative_time(seconds)
              return 'a minute ago' if seconds < 60

              interval = TIME_INTERVALS.find { |i| seconds < i[:max] }
              value = [seconds / interval[:div], 1].max
              value == 1 ? interval[:singular] : format(interval[:plural], value)
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
  end
end
