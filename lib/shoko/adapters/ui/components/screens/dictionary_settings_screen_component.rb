# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative '../../../../application/ports/inbound/menu_catalog'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/status_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative 'dictionary_settings_screen_component/action_values'
require_relative 'dictionary_settings_screen_component/list_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Dictionary settings + catalog download screen.
          class DictionarySettingsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include DictionarySettingsScreenComponentActionValues
            UI = Adapters::Ui::Constants::Ui
            include DictionarySettingsScreenComponentListRenderer

            ActionItem = Data.define(:key, :label, :value, :action)

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
              frame.render_title(title: 'Dictionary')
              frame.render_divider

              render_settings(surface, bounds, layout)
              render_search(surface, bounds, layout)
              render_status(surface, bounds, layout)
              render_results(surface, bounds, layout)
              render_footer(surface, bounds, layout, frame: frame)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def dictionary_results
              menu_state_reader&.dictionary_results || []
            end

            def filtered_results
              query = dictionary_query.downcase
              return dictionary_results if query.empty?

              dictionary_results.select do |item|
                name = item[:name].to_s.downcase
                pair = "#{item[:source]}-#{item[:target]}".downcase
                name.include?(query) || pair.include?(query)
              end
            end

            def selected_index
              (menu_state_reader&.dictionary_selected || 0).to_i
            end

            def dictionary_query
              menu_state_reader&.dictionary_query.to_s
            end

            def dictionary_cursor
              cursor = menu_state_reader&.dictionary_cursor
              cursor ? cursor.to_i : dictionary_query.length
            end

            def dictionary_mode
              (menu_state_reader&.mode || :dictionary).to_sym
            end

            def search_active?
              dictionary_mode == :dictionary_search
            end

            def dictionary_status
              (menu_state_reader&.dictionary_status || :idle).to_sym
            end

            def dictionary_message
              menu_state_reader&.dictionary_message.to_s
            end

            def dictionary_progress
              (menu_state_reader&.dictionary_progress || 0.0).to_f
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def config_reader
              return @config_reader if @config_reader

              @config_reader = @dependencies&.config_reader
            end

            # Layout, formatting, and text helpers for dictionary settings.
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
