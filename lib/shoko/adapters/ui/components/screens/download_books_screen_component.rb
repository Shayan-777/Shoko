# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require 'shoko/shared/download_source_policy'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/text_sanitizer'
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
          # Centralized download screen for Gutendex search + download flow.
          class DownloadBooksScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            UI = Adapters::Ui::Constants::Ui

            BookItemCtx = Struct.new(:row, :book, :selected, :layout)

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @config_reader = nil
            end

            def do_render(surface, bounds)
              layout = layout_metrics(bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              frame.render_title(title: 'Download Books')
              frame.render_divider

              render_source(surface, bounds, layout)
              render_search(surface, bounds, layout)
              render_status(surface, bounds, layout)
              render_results(surface, bounds, layout)
              render_footer(surface, bounds, layout, frame: frame)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def results
              menu_state_reader&.download_results || []
            end

            def selected_index
              (menu_state_reader&.download_selected || 0).to_i
            end

            def download_status
              (menu_state_reader&.download_status || :idle).to_sym
            end

            def download_message
              menu_state_reader&.download_message.to_s
            end

            def download_count
              (menu_state_reader&.download_count || 0).to_i
            end

            def download_progress
              (menu_state_reader&.download_progress || 0.0).to_f
            end

            def search_query
              menu_state_reader&.download_query || ''
            end

            def search_cursor
              cursor = menu_state_reader&.download_cursor
              cursor ? cursor.to_i : search_query.length
            end

            def search_active?
              menu_state_reader&.mode == :download_search
            end

            def source_selection_active?
              menu_state_reader&.mode == :download_source_select
            end

            def selected_source_index
              max_index = source_options.length - 1
              (menu_state_reader&.download_source_selected || current_source_index).to_i.clamp(0, max_index)
            end

            def current_source
              Shoko::Shared::DownloadSourcePolicy.normalize(config_reader&.download_source) ||
                Shoko::Shared::DownloadSourcePolicy.default_id
            end

            def current_source_index
              source_options.index(current_source) || 0
            end

            def current_source_label
              Shoko::Shared::DownloadSourcePolicy.label_for(current_source)
            end

            def source_options
              Shoko::Shared::DownloadSourcePolicy.canonical_ids
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def config_reader
              return @config_reader if @config_reader

              @config_reader = @dependencies&.config_reader
            end

            # Data extraction helpers for download result rows.
            def extract_book_fields(book)
              {
                title: safe_text(value_for(book, :title, 'title', 'Untitled')),
                authors: safe_text(Array(value_for(book, :authors, 'authors', [])).join(', ')),
                languages: safe_text(Array(value_for(book, :languages, 'languages', [])).join(',')),
                meta: result_meta(book),
              }
            end

            def value_for(book, key_sym, key_str, default)
              return default unless book.is_a?(Hash)
              return book[key_sym] if book.key?(key_sym)
              return book[key_str] if book.key?(key_str)

              default
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
            end

            def result_meta(book)
              return safe_text(value_for(book, :extension, 'extension', '').to_s.upcase) if libgen_result?(book)

              value_for(book, :download_count, 'download_count', 0).to_i.to_s
            end

            def libgen_result?(book)
              value_for(book, :source, 'source', current_source) == :libgen
            end

            # Layout and status helpers for the download screen.
            def empty_state_message
              reset = Shoko::Shared::Terminal::Ansi::RESET
              case download_status
              when :searching
                "#{UI::COLOR_TEXT_WARNING}Searching #{current_source_label}...#{reset}"
              when :error
                "#{UI::COLOR_TEXT_ERROR}#{safe_text(download_message)}#{reset}"
              else
                idle_download_message(reset)
              end
            end

            def idle_download_message(reset)
              if search_query.strip.empty?
                "#{UI::COLOR_TEXT_DIM}No search results yet#{reset}"
              else
                "#{UI::COLOR_TEXT_DIM}No results for your search#{reset}"
              end
            end

            def status_label
              msg = safe_text(download_message)
              return [msg.empty? ? 'Searching...' : msg, UI::COLOR_TEXT_WARNING] if download_status == :searching
              return [msg.empty? ? 'Downloading...' : msg, UI::COLOR_TEXT_WARNING] if download_status == :downloading
              return [msg.empty? ? 'Request failed' : msg, UI::COLOR_TEXT_ERROR] if download_status == :error
              return [msg, UI::COLOR_TEXT_SUCCESS] if download_status == :done

              ['', UI::COLOR_TEXT_DIM]
            end

            def button_string(label, active:)
              bg = active ? UI::BUTTON_BG_ACTIVE : UI::BUTTON_BG_INACTIVE
              fg = active ? UI::BUTTON_FG_ACTIVE : UI::BUTTON_FG_INACTIVE
              "#{bg}#{fg} #{label} #{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def layout_metrics(bounds)
              column_spec = column_layout([bounds.width - 8, 86].min)
              content_width = column_spec[:content_width]
              {
                indent: MenuDesign::Layout.centered_indent(bounds, content_width),
                content_width: content_width,
                columns: column_spec[:columns],
                gap: column_spec[:gap],
              }.merge(download_layout_rows(bounds.height))
            end

            def download_layout_rows(height)
              source_row = download_source_row(height)
              search_row = source_row + 2 + source_option_row_count
              status_row = search_row + 2
              {
                header_row: 1,
                source_row: source_row,
                source_options_row: source_row + 1,
                search_row: search_row,
                status_row: status_row,
                progress_row: status_row + 1,
                header_row_list: status_row + 2,
                list_start_row: status_row + 4,
                footer_row: download_footer_row(height, status_row),
              }
            end

            def download_source_row(height)
              [(height / 6) - 1, 3].max
            end

            def source_option_row_count
              source_selection_active? ? source_options.length : 0
            end

            def download_footer_row(height, status_row)
              [height - 2, status_row + 6].max
            end

            def column_layout(content_width)
              gap = 3
              columns = { author: 18, lang: 6, meta: 8 }
              columns[:title] = [content_width - columns.values.sum - (gap * 3), 16].max
              {
                content_width: columns.values.sum + (gap * 3),
                columns: columns,
                gap: gap,
              }
            end

            def draw_list_header(surface, bounds, layout, row)
              return if row < 5

              cols = layout[:columns]
              headers = ['Title', 'Author', 'Lang', current_source == :libgen ? 'Fmt' : 'DLs']
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: row,
                indent: layout[:indent],
                headers: headers,
                widths: [cols[:title], cols[:author], cols[:lang], cols[:meta]],
                divider_char: '-'
              )
            end

            def footer_text
              shown = results.length
              query = safe_text(search_query).strip
              return 'Choose a source and press Enter' if source_selection_active?
              return "#{current_source_label} | #{shown} #{shown == 1 ? 'result' : 'results'}" if query.empty?

              "#{current_source_label} | Filter: #{query}"
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: "Search #{current_source_label}",
                query: search_query,
                cursor: search_cursor,
                row: layout[:search_row],
                indent: layout[:indent],
                width: layout[:content_width],
                active: search_active?
              )
            end

            def render_source(surface, bounds, layout)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              label = "#{UI::COLOR_TEXT_DIM}Source#{reset}"
              value = button_string(current_source_label, active: true)
              surface.write(bounds, layout[:source_row], layout[:indent], "#{label}  #{value}")
              return unless source_selection_active?

              render_source_options(surface, bounds, layout, reset)
            end

            def render_source_options(surface, bounds, layout, reset)
              row = layout[:source_options_row]
              source_options.each_with_index do |source, index|
                surface.write(bounds, row + index, layout[:indent] + 2, source_option_text(source, index, reset))
              end
            end

            def source_option_text(source, index, reset)
              selected = index == selected_source_index
              active = source == current_source
              prefix = if selected
                         "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::MENU_SELECTION_BG}#{UI::MENU_SELECTION_TEXT}"
                       else
                         UI::COLOR_TEXT_PRIMARY
                       end
              marker = active ? '[x]' : '[ ]'
              "#{prefix} #{marker} #{Shoko::Shared::DownloadSourcePolicy.label_for(source)} #{reset}"
            end

            def render_status(surface, bounds, layout)
              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: layout[:status_row],
                indent: layout[:indent],
                left: result_count_text,
                right: status_label.first,
                width: layout[:content_width],
                left_color: UI::COLOR_TEXT_DIM,
                right_color: status_label.last
              )
              render_progress(surface, bounds, layout) if download_progress.positive?
            end

            def result_count_text
              shown = results.length
              total = download_count
              return "Showing #{shown} of #{total}" if total.positive? && total != shown

              "Found #{shown} #{shown == 1 ? 'book' : 'books'}"
            end

            def render_progress(surface, bounds, layout)
              row = layout[:progress_row]
              return if row > bounds.bottom

              MenuDesign::ProgressRenderer.new(surface, bounds).render(
                row: row,
                indent: layout[:indent],
                width: layout[:content_width],
                progress: download_progress,
                filled_char: '=',
                empty_char: '-'
              )
            end

            def render_results(surface, bounds, layout)
              return render_empty_state(surface, bounds, layout) if results.empty?

              render_results_list(surface, bounds, layout, results)
            end

            def render_empty_state(surface, bounds, layout)
              row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
              surface.write(bounds, row, layout[:indent], empty_state_message)
            end

            def render_results_list(surface, bounds, layout, items)
              list_height = bounds.height - layout[:list_start_row] - 3
              return if list_height <= 0

              draw_list_header(surface, bounds, layout, layout[:header_row_list])
              visible_book_rows(items, list_height, layout).each do |row|
                render_book_item(surface, bounds, row)
              end
            end

            def visible_book_rows(items, list_height, layout)
              start_index, visible = Ui::ListHelpers.slice_visible(items, list_height, selected_index)
              visible.each_with_index.filter_map do |book, offset|
                build_book_row(layout, book, start_index, offset)
              end
            end

            def build_book_row(layout, book, start_index, offset)
              row = layout[:list_start_row] + offset
              return nil if row > layout[:footer_row] - 1

              DownloadBooksScreenComponent::BookItemCtx.new(
                row: row,
                book: book,
                selected: (start_index + offset) == selected_index,
                layout: layout
              )
            end

            def render_book_item(surface, bounds, ctx)
              cols = ctx.layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: ctx.row,
                indent: ctx.layout[:indent],
                cells: book_row_cells(ctx.book, cols),
                widths: [cols[:title], cols[:author], cols[:lang], cols[:meta]],
                selected: ctx.selected
              )
            end

            def book_row_cells(book, cols)
              fields = extract_book_fields(book)
              [
                padded_book_cell(fields[:title], cols[:title]),
                padded_book_cell(fields[:authors], cols[:author]),
                padded_book_cell(fields[:languages], cols[:lang]),
                pad_left(fields[:meta].to_s, cols[:meta]),
              ]
            end

            def padded_book_cell(text, width)
              pad_right(truncate_text(text, width), width)
            end

            def render_footer(_surface, bounds, layout, frame:)
              row = layout[:footer_row]
              return if row > bounds.bottom

              clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(footer_text, layout[:content_width])
              frame.render_footer(text: clipped, row: row, indent: layout[:indent])
            end
          end
        end
      end
    end
  end
end
