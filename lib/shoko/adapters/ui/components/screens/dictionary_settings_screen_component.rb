# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters::Ui::Components
    module Screens
      # Dictionary settings + catalog download screen.
      class DictionarySettingsScreenComponent < BaseComponent
        include Adapters::Ui::Constants::Ui
        include Ui::TextUtils

        ActionItem = Struct.new(:key, :label, :value, keyword_init: true)

        def initialize(dependencies: nil)
          super()
          @dependencies = dependencies
          @menu_state_reader = nil
          @config_reader = nil
        end

        def do_render(surface, bounds)
          layout = layout_metrics(bounds)

          render_header(surface, bounds, layout)
          render_settings(surface, bounds, layout)
          render_search(surface, bounds, layout)
          render_status(surface, bounds, layout)
          render_results(surface, bounds, layout)
          render_footer(surface, bounds, layout)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def action_items
          [
            ActionItem.new(key: :back, label: 'Back', value: 'Return to Settings'),
            ActionItem.new(key: :toggle_lookup, label: 'Lookup', value: lookup_value),
            ActionItem.new(key: :pair, label: 'Pair', value: pair_value),
            ActionItem.new(key: :storage, label: 'Storage', value: storage_value),
            ActionItem.new(key: :refresh, label: 'Refresh Catalog', value: refresh_value),
          ]
        end

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

        def render_header(surface, bounds, layout)
          reset = Terminal::ANSI::RESET
          surface.write(bounds, layout[:header_row], layout[:indent],
                        "#{COLOR_TEXT_ACCENT}Dictionary#{reset}")
        end

        def render_settings(surface, bounds, layout)
          reset = Terminal::ANSI::RESET
          surface.write(bounds, layout[:settings_header_row], layout[:indent],
                        "#{COLOR_TEXT_DIM}Settings#{reset}")

          action_items.each_with_index do |item, index|
            row = layout[:settings_start_row] + index
            render_action_row(surface, bounds, item, row, index)
          end
        end

        def render_action_row(surface, bounds, item, row, index)
          reset = Terminal::ANSI::RESET
          selected = selected_index == index
          label = item.label.to_s
          value_text = item.value.to_s
          line = format_action_line(label, value_text, layout_action_width(bounds))
          styled = if selected
                     "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_ACCENT}#{line}#{reset}"
                   else
                     "#{COLOR_TEXT_PRIMARY}#{line}#{reset}"
                   end
          surface.write(bounds, row, layout_indent(bounds), styled)
        end

        def render_search(surface, bounds, layout)
          reset = Terminal::ANSI::RESET
          surface.write(bounds, layout[:search_label_row], layout[:indent],
                        "#{COLOR_TEXT_DIM}Search dictionaries#{reset}")

          query = dictionary_query.dup
          cursor = dictionary_cursor.clamp(0, query.length)
          query.insert(cursor, '_')
          field = pad_right(query, layout[:content_width])
          style = search_active? ? SELECTION_HIGHLIGHT : COLOR_TEXT_DIM
          surface.write(bounds, layout[:search_field_row], layout[:indent], "#{style}#{field}#{reset}")
        end

        def render_status(surface, bounds, layout)
          reset = Terminal::ANSI::RESET
          row = layout[:status_row]
          return if row > bounds.bottom

          text = status_label
          surface.write(bounds, row, layout[:indent], "#{text}#{reset}")
          render_progress(surface, bounds, layout) if dictionary_progress.positive?
        end

        def render_progress(surface, bounds, layout)
          row = layout[:progress_row]
          return if row > bounds.bottom

          indent = layout[:indent]
          content_width = layout[:content_width]
          usable = [content_width, 10].max
          filled = (usable * dictionary_progress.clamp(0.0, 1.0)).round

          accent = Terminal::ANSI::BRIGHT_GREEN
          dim = Terminal::ANSI::DIM
          reset = Terminal::ANSI::RESET
          track = accent + ('=' * filled) + reset
          track << (dim + ('-' * (usable - filled)) + reset) if filled < usable
          surface.write(bounds, row, indent, track)
        end

        def render_results(surface, bounds, layout)
          items = filtered_results
          if items.empty?
            render_empty_state(surface, bounds, layout)
          else
            render_results_list(surface, bounds, layout, items)
          end
        end

        def render_empty_state(surface, bounds, layout)
          row = (bounds.height / 2).clamp(layout[:list_start_row], bounds.bottom - 2)
          message = empty_state_message
          surface.write(bounds, row, layout[:indent], message)
        end

        def render_results_list(surface, bounds, layout, items)
          list_height = bounds.height - layout[:list_start_row] - 3
          return if list_height <= 0

          action_count = action_items.length
          selection = selected_index - action_count
          selection = 0 if selection.negative?

          start_index, visible = Ui::ListHelpers.slice_visible(items, list_height, selection)
          draw_list_header(surface, bounds, layout)

          current_row = layout[:list_start_row]
          visible.each_with_index do |item, offset|
            item_index = start_index + offset
            selected = (item_index == selection) && selected_index >= action_count
            render_dictionary_item(surface, bounds, layout, item, current_row, selected)
            current_row += 1
            break if current_row > bounds.bottom
          end
        end

        def render_dictionary_item(surface, bounds, layout, item, row, selected)
          reset = Terminal::ANSI::RESET
          line = format_dictionary_line(item, layout)
          styled = if selected
                     "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_ACCENT}#{line}#{reset}"
                   else
                     "#{COLOR_TEXT_PRIMARY}#{line}#{reset}"
                   end
          surface.write(bounds, row, layout[:indent], styled)
        end

        def render_footer(surface, bounds, layout)
          row = layout[:footer_row]
          return if row > bounds.bottom

          reset = Terminal::ANSI::RESET
          hint = if search_active?
                   '[Enter] Apply  [/ or ESC] Back'
                 else
                   '[Enter] Download  [/] Search  [R] Refresh  [ESC] Back'
                 end
          clipped = Shoko::Shared::Terminal::TextMetrics.truncate_to(hint, layout[:content_width])
          surface.write(bounds, row, layout[:indent], "#{COLOR_TEXT_DIM}#{clipped}#{reset}")
        end

        def format_action_line(label, value, width)
          label_text = pad_right(label, [width / 2, 12].max)
          value_text = truncate_text(value, width - label_text.length - 1)
          "#{label_text} #{value_text}"
        end

        def format_dictionary_line(item, layout)
          cols = layout[:columns]
          gap = ' ' * layout[:gap]

          status = item[:installed] ? '[x]' : '[ ]'
          pair = format_pair(item)
          size = item[:size].to_s
          updated = item[:updated].to_s
          note = item[:installed] ? 'installed' : 'download'

          parts = [
            pad_right(status, cols[:status]),
            pad_right(pair, cols[:pair]),
            pad_right(size, cols[:size]),
            pad_right(updated, cols[:updated]),
            pad_right(note, cols[:note]),
          ]

          parts.join(gap)
        end

        def format_pair(item)
          src = item[:source].to_s.upcase
          tgt = item[:target].to_s.upcase
          return item[:name].to_s if src.empty? || tgt.empty?

          "#{src}-#{tgt}"
        end

        def empty_state_message
          reset = Terminal::ANSI::RESET
          case dictionary_status
          when :loading
            "#{COLOR_TEXT_WARNING}Loading dictionary list...#{reset}"
          when :error
            "#{COLOR_TEXT_ERROR}#{dictionary_message}#{reset}"
          else
            if dictionary_query.strip.empty?
              "#{COLOR_TEXT_DIM}Press R to load dictionaries#{reset}"
            else
              "#{COLOR_TEXT_DIM}No results for your search#{reset}"
            end
          end
        end

        def status_label
          reset = Terminal::ANSI::RESET
          case dictionary_status
          when :loading
            "#{COLOR_TEXT_WARNING}Loading...#{reset}"
          when :downloading
            "#{COLOR_TEXT_WARNING}#{dictionary_message}#{reset}"
          when :error
            "#{COLOR_TEXT_ERROR}#{dictionary_message}#{reset}"
          else
            message = dictionary_message.to_s.strip
            if message.empty?
              count = filtered_results.length
              "#{COLOR_TEXT_DIM}#{count} dictionaries#{reset}"
            else
              "#{COLOR_TEXT_DIM}#{message}#{reset}"
            end
          end
        end

        def lookup_value
          backend = config_reader&.dictionary_backend
          backend_name = backend.to_s.downcase
          runtime_override = runtime_config&.dictionary_backend_override.to_s.downcase
          sqlite_ready = dictionary_availability&.sqlite3_available?

          return 'Disabled' if runtime_override == 'disabled' || backend_name == 'disabled'
          return 'Needs sqlite3' unless sqlite_ready
          return sqlite3_status if runtime_override == 'sqlite' || backend_name == 'sqlite'

          dictionary_auto_status
        end

        def dictionary_auto_status
          return sqlite3_status if dictionary_datasets_present?

          'Enabled (no datasets)'
        end

        def dictionary_datasets_present?
          path = config_reader&.dictionary_path
          dictionary_storage&.databases_present?(path)
        rescue StandardError
          false
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

        def menu_state_reader
          return @menu_state_reader if @menu_state_reader

          @menu_state_reader = @dependencies&.menu_state_reader
        end

        def config_reader
          return @config_reader if @config_reader

          @config_reader = @dependencies&.config_reader
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

        def refresh_value
          dictionary_status == :loading ? 'Loading...' : 'Fetch latest list'
        end

        def default_storage_path
          dictionary_storage&.default_databases_path.to_s
        rescue StandardError
          ''
        end

        def display_path(path)
          dictionary_storage&.display_path(path).to_s
        rescue StandardError
          path.to_s
        end

        def dictionary_auto_setting?(value)
          return true if value.nil?

          str = value.to_s.strip
          str.empty? || str.casecmp('auto').zero?
        end

        def layout_metrics(bounds)
          width = bounds.width
          content_width = [width - 4, 40].max
          indent = ((width - content_width) / 2).clamp(2, [width - 2, 2].max)

          columns = {
            status: 4,
            pair: 8,
            size: 6,
            updated: 12,
          }
          gap = 2
          used = columns.values.sum + (gap * 4) + 10
          columns[:note] = [content_width - used, 8].max

          {
            indent: indent,
            content_width: content_width,
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
            columns: columns,
            gap: gap,
          }
        end

        def draw_list_header(surface, bounds, layout)
          row = layout[:header_row_list]
          return if row > bounds.bottom

          indent = layout[:indent]
          cols = layout[:columns]
          gap = ' ' * layout[:gap]
          headers = [
            pad_right('St', cols[:status]),
            pad_right('Pair', cols[:pair]),
            pad_right('Size', cols[:size]),
            pad_right('Updated', cols[:updated]),
            pad_right('Status', cols[:note]),
          ].join(gap)

          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::DEFAULT_FG
          padded = pad_right(headers, layout[:content_width])
          surface.write(bounds, row, indent, header_style + padded + Terminal::ANSI::RESET)
          divider = ('-' * [layout[:content_width], 1].max)
          surface.write(bounds, row + 1, indent, COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET)
        end

        def layout_action_width(bounds)
          [bounds.width - 4, 40].max
        end

        def layout_indent(bounds)
          width = bounds.width
          content_width = layout_action_width(bounds)
          ((width - content_width) / 2).clamp(2, [width - 2, 2].max)
        end
      end
    end
  end
end
