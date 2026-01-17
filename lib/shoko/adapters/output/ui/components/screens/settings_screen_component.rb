# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Settings screen component for configuration management
      class SettingsScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::UI

        SettingsItem = Struct.new(:action, :icon, :label, keyword_init: true)

        SETTINGS_ITEMS = [
          SettingsItem.new(action: :back_to_menu, icon: '', label: 'Go Back'),
          SettingsItem.new(action: :toggle_view_mode, icon: '', label: 'View Mode'),
          SettingsItem.new(action: :cycle_line_spacing, icon: '', label: 'Line Spacing'),
          SettingsItem.new(action: :toggle_page_numbering_mode, icon: '', label: 'Page Numbering Mode'),
          SettingsItem.new(action: :toggle_page_numbers, icon: '', label: 'Page Numbers'),
          SettingsItem.new(action: :toggle_highlight_quotes, icon: '', label: 'Text Highlighting'),
          SettingsItem.new(action: :open_dictionary_settings, icon: '', label: 'Dictionary'),
          SettingsItem.new(action: :toggle_kitty_images, icon: '', label: 'Kitty Images'),
          SettingsItem.new(action: :wipe_cache, icon: '', label: 'Wipe Cache'),
        ].freeze

        ItemCtx = Struct.new(:row, :item, :value_text, :value_color, :index, :selected, :indent, keyword_init: true)

        def initialize(state, catalog_service = nil)
          super()
          @state = state
          @catalog = catalog_service
        end

        def do_render(surface, bounds)
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}Settings#{Terminal::ANSI::RESET}")

          selected = @state.get(%i[menu settings_selected]) || 1
          text_values = setting_value_map
          render_settings(surface, bounds, selected, text_values)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def render_settings(surface, bounds, selected, text_values)
          metrics = layout_metrics(bounds, text_values)
          indent = metrics[:indent]
          max_index = SETTINGS_ITEMS.length - 1
          cursor = selected.clamp(0, max_index)
          row = metrics[:start_row]
          insert_toggle_gap = false

          SETTINGS_ITEMS.each_with_index do |item, index|
            break if row >= metrics[:max_row]

            action = item.action
            is_selected = cursor == index
            case action
            when :toggle_view_mode
              row = render_button_group(surface, bounds, item, row, indent, is_selected,
                                        current_view_mode, view_mode_buttons)
              insert_toggle_gap = false
            when :cycle_line_spacing
              row = render_button_group(surface, bounds, item, row, indent, is_selected,
                                        current_line_spacing, line_spacing_buttons)
              insert_toggle_gap = false
            when :toggle_page_numbering_mode
              row = render_button_group(surface, bounds, item, row, indent, is_selected,
                                        current_page_numbering_mode, page_numbering_buttons)
              insert_toggle_gap = true
            else
              if toggled_action?(action) && insert_toggle_gap
                row += 1
                insert_toggle_gap = false
              end
              value_text, value_color = text_values[action]
              ctx = ItemCtx.new(row: row, item: item, value_text: value_text, value_color: value_color,
                                index: index, selected: is_selected, indent: indent)
              row = render_text_item(surface, bounds, ctx)
            end
          end
        end

        def render_text_item(surface, bounds, ctx)
          text = formatted_row(ctx.item, ctx.value_text, ctx.value_color, ctx.selected)
          row = ctx.row
          surface.write(bounds, row, ctx.indent, text)
          row + 2
        end

        def formatted_row(item, value_text, value_color, selected)
          label = label_text(item)
          colors = row_colors(selected)
          line = "#{colors[:prefix]}#{colors[:fg]}#{label}"
          line = "#{line}#{Terminal::ANSI::RESET}  #{value_color}#{value_text}" if value_text && !value_text.to_s.empty?
          "#{line}#{Terminal::ANSI::RESET}"
        end

        def row_colors(selected)
          if selected
            { prefix: Terminal::ANSI::BOLD, fg: COLOR_TEXT_ACCENT }
          else
            { prefix: '', fg: COLOR_TEXT_PRIMARY }
          end
        end

        def label_text(item)
          "#{item.icon}  #{item.label}"
        end

        def layout_metrics(bounds, text_values)
          height = bounds.height
          width = bounds.width
          label_width = SETTINGS_ITEMS.map { |item| display_width(label_text(item)) }.max || 0
          text_value_width = text_values.values.map { |value| display_width(Array(value).first) }.max || 0
          button_width = [
            button_group_width(view_mode_buttons),
            button_group_width(line_spacing_buttons),
            button_group_width(page_numbering_buttons),
          ].max || 0
          content_width = label_width + 2 + [text_value_width, button_width].max
          available = width - content_width
          indent = (available / 2).floor
          indent = indent.clamp(2, [available, 0].max)
          content_rows = estimated_content_rows
          {
            indent: indent,
            start_row: [(height - content_rows) / 2, 4].max,
            max_row: height - 3,
          }
        end

        def display_width(text)
          Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text.to_s)
        end

        def setting_value_map
          {
            back_to_menu: ['Return to main menu', COLOR_TEXT_DIM],
            toggle_page_numbers: toggle_page_number_value,
            toggle_highlight_quotes: toggle_highlight_value,
            open_dictionary_settings: ['Configure & download dictionaries', COLOR_TEXT_DIM],
            toggle_kitty_images: toggle_kitty_images_value,
            wipe_cache: ['Removes EPUB + scan caches', COLOR_TEXT_WARNING],
          }
        end

        def render_button_group(surface, bounds, item, row, indent, selected, current_value, buttons)
          colors = row_colors(selected)
          label = "#{colors[:prefix]}#{colors[:fg]}#{label_text(item)}#{Terminal::ANSI::RESET}"
          surface.write(bounds, row, indent, label)
          buttons_line = button_row(buttons, current_value)
          next_row = row + 1
          surface.write(bounds, next_row, indent, buttons_line) if next_row < bounds.height
          row + 3
        end

        def button_row(buttons, current_value)
          buttons.map { |value, label| button_string(label, value == current_value) }.join(' ')
        end

        def button_string(label, active)
          bg = active ? BUTTON_BG_ACTIVE : BUTTON_BG_INACTIVE
          fg = active ? BUTTON_FG_ACTIVE : BUTTON_FG_INACTIVE
          "#{bg}#{fg} #{label} #{Terminal::ANSI::RESET}"
        end

        def button_group_width(buttons)
          buttons.sum do |_value, label|
            Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(label) + 2
          end + (buttons.length - 1)
        end

        def toggled_action?(action)
          %i[toggle_page_numbers toggle_highlight_quotes toggle_kitty_images].include?(action)
        end

        def view_mode_buttons
          [[:split, 'Split'], [:single, 'Single']]
        end

        def line_spacing_buttons
          [[:normal, 'Normal'], [:relaxed, 'Relaxed'], [:compact, 'Compact']]
        end

        def page_numbering_buttons
          [[:absolute, 'Absolute'], [:dynamic, 'Dynamic']]
        end

        def current_view_mode
          @state.get(%i[config view_mode]) || :split
        end

        def current_line_spacing
          @state.get(%i[config line_spacing]) || :compact
        end

        def current_page_numbering_mode
          @state.get(%i[config page_numbering_mode]) || :dynamic
        end

        def toggle_page_number_value
          text = format_page_numbers
          color = text == 'Enabled' ? COLOR_TEXT_SUCCESS : COLOR_TEXT_WARNING
          [text, color]
        end

        def toggle_highlight_value
          text = format_highlight_quotes
          color = text == 'On' ? COLOR_TEXT_SUCCESS : COLOR_TEXT_WARNING
          [text, color]
        end

        def format_page_numbers
          @state.get(%i[config show_page_numbers]) ? 'Enabled' : 'Disabled'
        end

        def format_highlight_quotes
          value = @state.get(%i[config highlight_quotes])
          if value.nil? || !!value
            'On'
          else
            'Off'
          end
        end

        def toggle_kitty_images_value
          enabled = !@state.get(%i[config kitty_images]).nil?
          text = enabled ? 'Enabled' : 'Disabled'
          color = enabled ? COLOR_TEXT_SUCCESS : COLOR_TEXT_DIM
          [text, color]
        end

        def estimated_content_rows
          button_actions = %i[toggle_view_mode cycle_line_spacing toggle_page_numbering_mode]
          base = SETTINGS_ITEMS.sum do |item|
            button_actions.include?(item.action) ? 3 : 2
          end

          has_post_toggle = SETTINGS_ITEMS.any? { |item| toggled_action?(item.action) }
          base += 1 if has_post_toggle
          base
        end
      end
    end
  end
end
