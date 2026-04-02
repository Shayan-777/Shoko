# frozen_string_literal: true

require_relative '../../../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Layout, formatting, and text helpers for dictionary settings.
          module DictionarySettingsScreenComponentLayoutSupport
            UI = Adapters::Ui::Constants::Ui

            private

            def format_action_line(label, value, width)
              label_text = pad_right(label, [width / 2, 12].max)
              value_text = truncate_text(value, width - label_text.length - 1)
              "#{label_text} #{value_text}"
            end

            def build_dictionary_cells(item, cols)
              values = dictionary_cell_values(item)
              [
                pad_right(values[:status], cols[:status]),
                pad_right(values[:pair], cols[:pair]),
                pad_right(values[:size], cols[:size]),
                pad_right(values[:updated], cols[:updated]),
                pad_right(values[:note], cols[:note]),
              ]
            end

            def dictionary_cell_values(item)
              {
                status: item[:installed] ? '[x]' : '[ ]',
                pair: format_pair(item),
                size: item[:size].to_s,
                updated: item[:updated].to_s,
                note: item[:installed] ? 'installed' : 'download',
              }
            end

            def format_pair(item)
              src = item[:source].to_s.upcase
              tgt = item[:target].to_s.upcase
              return item[:name].to_s if src.empty? || tgt.empty?

              "#{src}-#{tgt}"
            end

            def empty_state_message
              reset = Shoko::Shared::Terminal::Ansi::RESET
              case dictionary_status
              when :loading
                "#{UI::COLOR_TEXT_WARNING}Loading dictionary list...#{reset}"
              when :error
                "#{UI::COLOR_TEXT_ERROR}#{dictionary_message}#{reset}"
              else
                idle_dictionary_message(reset)
              end
            end

            def idle_dictionary_message(reset)
              if dictionary_query.strip.empty?
                "#{UI::COLOR_TEXT_DIM}Dictionary catalog idle#{reset}"
              else
                "#{UI::COLOR_TEXT_DIM}No results for your search#{reset}"
              end
            end

            def status_label
              return 'Loading...' if dictionary_status == :loading
              return dictionary_message if %i[downloading error].include?(dictionary_status)

              status_summary_message
            end

            def status_summary_message
              message = dictionary_message.to_s.strip
              return message unless message.empty?

              "#{filtered_results.length} dictionaries"
            end

            def layout_metrics(bounds)
              content_width = [bounds.width - 4, 40].max
              dictionary_layout_rows(bounds).merge(
                indent: ((bounds.width - content_width) / 2).clamp(2, [bounds.width - 2, 2].max),
                content_width: content_width,
                columns: dictionary_columns(content_width),
                gap: 2
              )
            end

            def dictionary_layout_rows(bounds)
              {
                header_row: 2,
                settings_header_row: 4,
                settings_start_row: 5,
                search_label_row: 11,
                search_field_row: 12,
                status_row: 14,
                progress_row: 15,
                header_row_list: 16,
                list_start_row: 18,
                footer_row: bounds.bottom - 1,
              }
            end

            def dictionary_columns(content_width)
              columns = { status: 4, pair: 8, size: 6, updated: 12 }
              columns[:note] = [content_width - columns.values.sum - 18, 8].max
              columns
            end

            def draw_list_header(surface, bounds, layout)
              row = layout[:header_row_list]
              return if row > bounds.bottom

              cols = layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: row,
                indent: layout[:indent],
                headers: %w[St Pair Size Updated Status],
                widths: [cols[:status], cols[:pair], cols[:size], cols[:updated], cols[:note]],
                divider_char: '-'
              )
            end

            def layout_action_width(bounds)
              [bounds.width - 4, 40].max
            end

            def layout_indent(bounds)
              content_width = layout_action_width(bounds)
              ((bounds.width - content_width) / 2).clamp(2, [bounds.width - 2, 2].max)
            end

            def footer_text
              query = Shoko::Shared::Terminal::TextSanitizer.sanitize(
                dictionary_query,
                preserve_newlines: false,
                preserve_tabs: false
              ).strip
              count = filtered_results.length
              return "#{count} #{count == 1 ? 'result' : 'results'}" if query.empty?

              "Filter: #{query}"
            end
          end
        end
      end
    end
  end
end
