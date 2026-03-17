# frozen_string_literal: true

require 'time'

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/table_renderer'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative '../../../../shared/terminal/text_sanitizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Library screen component that renders cached books with an optional
          # metadata inspector.
          class LibraryScreenComponent < BaseScreenComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path)

            TIME_INTERVALS = [
              { max: 3600, div: 60, singular: 'a minute ago', plural: '%d minutes ago' },
              { max: 86_400, div: 3600, singular: 'an hour ago', plural: '%d hours ago' },
              { max: 604_800, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
              { max: Float::INFINITY, div: 604_800, singular: 'a week ago', plural: '%d weeks ago' },
            ].freeze
            DETAIL_KEY_WIDTH = 9

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
              shell = MenuDesign::MasterDetailShell.new(surface, bounds)
              layout = shell.build_layout(
                detail_visible: details_open,
                desired_detail_width: 32,
                min_primary_width: 34,
                min_detail_width: 28,
                stacked_detail_height: 9
              )

              shell.render_frame(
                layout: layout,
                title: 'Library',
                hint: 'ENTER open  SPACE details  ESC back',
                summary_left: "#{items.length} cached #{items.length == 1 ? 'book' : 'books'}",
                summary_right: details_open ? 'Inspector visible' : 'SPACE shows metadata',
                footer: footer_text(items.length, details_open)
              )
              shell.render_panels(
                layout: layout,
                primary_title: 'Cached Books',
                secondary_title: 'Details'
              )

              if items.empty?
                render_empty(surface, bounds, layout.primary_panel.content)
              else
                render_library(surface, bounds, layout.primary_panel.content, items, selected)
              end

              render_details_panel(
                surface,
                bounds,
                layout.secondary_panel&.content,
                items[selected],
                selected,
                items.length
              )
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
              return entry[key] if entry.is_a?(Struct)
              return entry.to_h[key] if entry.is_a?(Data)

              normalized = entry.each_with_object({}) do |(entry_key, value), result|
                result[entry_key.is_a?(String) ? entry_key.to_sym : entry_key] = value
              end
              normalized[key]
            end

            def selected_index(total)
              return 0 if total <= 0

              current = (menu_state_reader&.browse_selected || 0).to_i
              current.clamp(0, total - 1)
            end

            def details_open?
              reader = menu_state_reader
              reader&.library_details_open? == true
            end

            def footer_text(count, details_open)
              noun = count == 1 ? 'book' : 'books'
              details_open ? "#{count} cached #{noun} • inspector open" : "#{count} cached #{noun}"
            end

            def render_empty(surface, bounds, panel)
              row = panel.y + [panel.height / 2, 0].max
              surface.write(bounds, row, panel.x,
                            "#{Adapters::Ui::Constants::Ui::COLOR_TEXT_DIM}No cached books yet#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def render_library(surface, bounds, panel, items, selected)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: ['Title'],
                widths: [panel.width],
                divider_char: '─'
              )

              visible_rows = [panel.height - 2, 0].max
              return if visible_rows <= 0

              start_index, visible = Ui::ListHelpers.slice_visible(items, visible_rows, selected)
              current_row = panel.y + 2
              visible.each_with_index do |book, offset|
                break if current_row > panel.bottom

                absolute_index = start_index + offset
                title = safe_text(book.title || 'Untitled')
                decorated = "#{pad_left((absolute_index + 1).to_s, 3)}  #{title}"
                MenuDesign::TableRenderer.new(surface, bounds).render_row(
                  row: current_row,
                  indent: panel.x,
                  cells: [pad_right(truncate_text(decorated, panel.width), panel.width)],
                  widths: [panel.width],
                  selected: absolute_index == selected
                )
                current_row += 1
              end
            end

            def render_details_panel(surface, bounds, panel, item, selected, total)
              return unless panel && item

              lines = details_lines(item, selected, total, panel.width)
              row = panel.y
              lines.each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, "#{COLOR_TEXT_PRIMARY}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
            end

            def details_lines(item, selected, total, inner_width)
              lines = []
              title = safe_text(item.title || 'Untitled')
              lines.concat(wrap_text(title, inner_width).map do |line|
                "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}"
              end)
              subtitle = "Book #{selected + 1} of #{total}"
              lines << "#{COLOR_TEXT_DIM}#{subtitle}#{Shoko::Shared::Terminal::Ansi::RESET}"
              lines << ''

              append_detail(lines, 'Authors', item.authors, inner_width)
              append_detail(lines, 'Year', item.year, inner_width)
              append_detail(lines, 'Accessed', relative_accessed_label(item.last_accessed), inner_width)
              append_detail(lines, 'Size', format_size(item.size_bytes), inner_width)
              append_detail(lines, 'Cache', compact_path(item.open_path), inner_width)
              append_detail(lines, 'EPUB', compact_path(item.epub_path), inner_width)
              lines
            end

            def append_detail(lines, label, value, width)
              safe_value = safe_text(value.to_s.strip)
              safe_value = '—' if safe_value.empty?
              value_width = [width - DETAIL_KEY_WIDTH - 1, 8].max
              wrapped = wrap_text(safe_value, value_width)
              wrapped = ['—'] if wrapped.empty?
              wrapped.each_with_index do |part, index|
                key = index.zero? ? pad_right("#{label}:", DETAIL_KEY_WIDTH) : ' ' * DETAIL_KEY_WIDTH
                lines << "#{key}#{truncate_text(part, value_width)}"
              end
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
            end

            def format_relative_time(seconds)
              return 'a minute ago' if seconds < 60

              interval = TIME_INTERVALS.find { |entry| seconds < entry[:max] }
              value = [seconds / interval[:div], 1].max
              value == 1 ? interval[:singular] : format(interval[:plural], value)
            end

            public

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
