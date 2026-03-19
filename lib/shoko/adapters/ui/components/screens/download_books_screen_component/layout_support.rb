# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Layout and status helpers for the download screen.
          module DownloadBooksScreenComponentLayoutSupport
            UI = Adapters::Ui::Constants::Ui

            private

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
          end
        end
      end
    end
  end
end
