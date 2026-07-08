# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../rect'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/canvas_well'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/list_helpers'
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
          class LibraryScreenComponent < BaseScreenComponent
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

            Status = Shoko::Shared::PrepaginationStatus
            TextMetrics = Shoko::Shared::Terminal::TextMetrics
            Spinner = Shoko::Adapters::Ui::Components::Ui::Spinner

            def initialize(dependencies, menu_visual_profile: nil)
              super(dependencies)
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @catalog = dependencies&.catalog_service
              @items = nil
              @menu_state_reader = nil
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
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
              @dependencies.respond_to?(:menu_hit_registry) ? @dependencies.menu_hit_registry : nil
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
              start_index, visible = Ui::ListHelpers.slice_visible(items, height, selected)
              visible.each_with_index do |item, offset|
                render_row(list, frame, item: item, index: start_index + offset,
                                        row: top + offset, selected: start_index + offset == selected)
              end
              return if details_open?

              list.render_scrollbar(top: top, height: height, total: items.length,
                                    visible: height, offset: start_index)
            end

            def render_row(list, frame, item:, index:, row:, selected:)
              status = prepagination_status_for(item)
              title_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              list.row(
                row: row,
                left: [[row_marker(status, index), Palette::LANDING_DIM_FG], ['  ', nil],
                       [safe_text(item.title.to_s.empty? ? 'Untitled' : item.title), title_fg],
                       [status_label(status), accent]],
                right: [[relative_accessed_label(item.last_accessed), Palette::LANDING_DIM_FG]],
                selected: selected,
                action: { type: :list_row, list: :library, index: index },
                width: list_width(frame)
              )
            end

            def render_empty(frame, top, height)
              frame.write_line(top + [height / 2, 0].max - 1, [['No cached books yet', Palette::LANDING_DIM_FG]])
            end

            # ----- inspector well -----

            def render_details_well(surface, bounds, frame, item)
              return unless item

              rect = well_rect(frame, bounds)
              return if rect.width < 20

              well = MenuDesign::CanvasWell.new(surface, bounds, rect: rect)
              well.paint(title: well.truncate(safe_text(item.title || 'Untitled')), accent: accent)
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
              safe_value = safe_text(value.to_s.strip)
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

              normalized = entry.transform_keys do |entry_key|
                entry_key.is_a?(String) ? entry_key.to_sym : entry_key
              end
              normalized[key]
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
              return Status::READY unless reader.respond_to?(:prepaginate_active)

              Status.for_path(
                item.epub_path,
                paths: reader.prepaginate_paths,
                done: reader.prepaginate_done,
                active: reader.prepaginate_active == true
              )
            end

            def row_marker(status, index)
              case status
              when Status::IN_PROGRESS then pad_left(Spinner.glyph, 3)
              when Status::QUEUED then pad_left(queued_glyph, 3)
              else pad_left((index + 1).to_s, 3)
              end
            end

            def status_label(status)
              case status
              when Status::IN_PROGRESS then '  · recalculating'
              when Status::QUEUED then '  · queued'
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

              safe_text(File.basename(value))
            end

            def format_size(bytes)
              format('%.1f MB', (bytes.to_f / (1024 * 1024)).round(1))
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text.to_s, preserve_newlines: false,
                                                                         preserve_tabs: false)
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end
          end
        end
      end
    end
  end
end
