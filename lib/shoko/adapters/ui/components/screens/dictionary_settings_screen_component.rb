# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/shared/terminal/text_sanitizer'
require 'shoko/application/ports/inbound/menu_catalog'
require_relative '../menu_design/frame_renderer'
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
          # Dictionary settings + catalog download screen.
          class DictionarySettingsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            UI = Adapters::Ui::Constants::Ui

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

            ACTION_VALUE_HELPERS = {
              back_value: :back_value,
              lookup_value: :lookup_value,
              pair_value: :pair_value,
              storage_value: :storage_value,
              refresh_value: :refresh_value,
            }.freeze

            ActionRow = Data.define(:item, :row, :selected, :width, :indent)
            ResultRow = Data.define(:item, :row, :selected, :layout)

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

            def action_items
              Shoko::Application::Ports::Inbound::MenuCatalog.dictionary_action_items.map do |item|
                DictionarySettingsScreenComponent::ActionItem.new(
                  key: item.key,
                  label: item.label,
                  value: action_value_for(item.value_key),
                  action: item.action
                )
              end
            end

            def action_value_for(value_key)
              helper = ACTION_VALUE_HELPERS[value_key.to_sym]
              helper ? send(helper) : ''
            end

            def back_value
              'Return'
            end

            def lookup_value
              backend_name = config_reader&.dictionary_backend.to_s.downcase
              runtime_override = runtime_config&.dictionary_backend_override.to_s.downcase
              return 'Disabled' if disabled_dictionary_backend?(backend_name, runtime_override)
              return 'Needs sqlite3' unless dictionary_availability&.sqlite3_available?
              return sqlite3_status if sqlite_dictionary_backend?(backend_name, runtime_override)

              dictionary_auto_status
            end

            def disabled_dictionary_backend?(backend_name, runtime_override)
              runtime_override == 'disabled' || backend_name == 'disabled'
            end

            def sqlite_dictionary_backend?(backend_name, runtime_override)
              runtime_override == 'sqlite' || backend_name == 'sqlite'
            end

            def dictionary_auto_status
              return sqlite3_status if dictionary_datasets_present?

              'Enabled (no datasets)'
            end

            def dictionary_datasets_present?
              dictionary_storage&.databases_present?(config_reader&.dictionary_path)
            end

            def sqlite3_status
              dictionary_availability&.sqlite3_available? ? 'Enabled' : 'Needs sqlite3'
            end

            def pair_value
              source = config_reader&.dictionary_source_lang
              target = config_reader&.dictionary_target_lang
              src = dictionary_auto_setting?(source) ? 'Auto' : source.to_s.upcase
              tgt = target.to_s.strip.empty? ? 'EN' : target.to_s.upcase
              "#{src} → #{tgt}"
            end

            def storage_value
              path = config_reader&.dictionary_path.to_s.strip
              return "Default (#{display_path(default_storage_path)})" if path.empty?

              display_path(path)
            end

            def refresh_value
              dictionary_status == :loading ? 'Loading...' : 'Fetch latest list'
            end

            def runtime_config
              return @runtime_config if defined?(@runtime_config)

              @runtime_config = @dependencies&.runtime_config
            end

            def dictionary_availability
              return @dictionary_availability if defined?(@dictionary_availability)

              @dictionary_availability = @dependencies&.dictionary_availability
            end

            def dictionary_storage
              return @dictionary_storage if defined?(@dictionary_storage)

              @dictionary_storage = @dependencies&.dictionary_storage
            end

            def default_storage_path
              dictionary_storage&.default_databases_path.to_s
            end

            def display_path(path)
              dictionary_storage&.display_path(path).to_s
            end

            def dictionary_auto_setting?(value)
              return true if value.nil?

              str = value.to_s.strip
              str.empty? || str.casecmp('auto').zero?
            end

            def render_settings(surface, bounds, layout)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              surface.write(
                bounds,
                layout[:settings_header_row],
                layout[:indent],
                "#{UI::COLOR_TEXT_DIM}Settings#{reset}"
              )

              action_rows(bounds, layout).each { |row| render_action_row(surface, bounds, row) }
            end

            def action_rows(bounds, layout)
              action_items.each_with_index.map do |item, index|
                ActionRow.new(
                  item: item,
                  row: layout[:settings_start_row] + index,
                  selected: selected_index == index,
                  width: layout_action_width(bounds),
                  indent: layout_indent(bounds)
                )
              end
            end

            def render_action_row(surface, bounds, row)
              reset = Shoko::Shared::Terminal::Ansi::RESET
              line = format_action_line(row.item.label.to_s, row.item.value.to_s, row.width)
              styled = if row.selected
                         selected_action_text(line, reset)
                       else
                         "#{UI::COLOR_TEXT_PRIMARY} #{line} #{reset}"
                       end
              surface.write(bounds, row.row, row.indent, styled)
            end

            def selected_action_text(line, reset)
              "#{Shoko::Shared::Terminal::Ansi::BOLD}#{UI::MENU_SELECTION_BG}" \
                "#{UI::MENU_SELECTION_TEXT} #{line} #{reset}"
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search dictionaries',
                query: dictionary_query,
                cursor: dictionary_cursor,
                row: layout[:search_label_row],
                indent: layout[:indent],
                width: layout[:content_width],
                active: search_active?
              )
            end

            def render_status(surface, bounds, layout)
              row = layout[:status_row]
              return if row > bounds.bottom

              MenuDesign::StatusRenderer.new(surface, bounds).render_status(
                row: row,
                indent: layout[:indent],
                left: status_label,
                width: layout[:content_width]
              )
              render_progress(surface, bounds, layout) if dictionary_progress.positive?
            end

            def render_progress(surface, bounds, layout)
              row = layout[:progress_row]
              return if row > bounds.bottom

              MenuDesign::ProgressRenderer.new(surface, bounds).render(
                row: row,
                indent: layout[:indent],
                width: layout[:content_width],
                progress: dictionary_progress,
                filled_char: '=',
                empty_char: '-'
              )
            end

            def render_results(surface, bounds, layout)
              items = filtered_results
              return render_empty_state(surface, bounds, layout) if items.empty?

              render_results_list(surface, bounds, layout, items)
            end

            def render_empty_state(surface, bounds, layout)
              row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
              surface.write(bounds, row, layout[:indent], empty_state_message)
            end

            def render_results_list(surface, bounds, layout, items)
              list_height = bounds.height - layout[:list_start_row] - 3
              return if list_height <= 0

              draw_list_header(surface, bounds, layout)
              visible_result_rows(layout, items, list_height).each do |row|
                render_dictionary_item(surface, bounds, row)
              end
            end

            def visible_result_rows(layout, items, list_height)
              selection = [selected_index - action_items.length, 0].max
              start_index, visible = Ui::ListHelpers.slice_visible(items, list_height, selection)
              visible.each_with_index.filter_map do |item, offset|
                build_result_row(layout, item, start_index, offset)
              end
            end

            def build_result_row(layout, item, start_index, offset)
              row = layout[:list_start_row] + offset
              return nil if row > layout[:footer_row] - 1

              absolute_index = start_index + offset
              ResultRow.new(
                item: item,
                row: row,
                selected: absolute_index == [selected_index - action_items.length, 0].max &&
                  selected_index >= action_items.length,
                layout: layout
              )
            end

            def render_dictionary_item(surface, bounds, row)
              columns = row.layout[:columns]
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.layout[:indent],
                cells: build_dictionary_cells(row.item, columns),
                widths: [columns[:status], columns[:pair], columns[:size], columns[:updated], columns[:note]],
                selected: row.selected,
                pointer: true
              )
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
