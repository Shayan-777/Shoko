# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../shared/menu_definitions'
require_relative '../menu_design/frame_renderer'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/layout'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Settings screen component for configuration management
          class SettingsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui

            SETTINGS_ITEMS = Shoko::Shared::MenuDefinitions.settings_items

            ItemCtx = Struct.new(:row, :item, :value_text, :value_color, :index, :selected, :indent, keyword_init: true)
            CHECKBOX_UNCHECKED = '󰄱'
            CHECKBOX_CHECKED = '󰱒'
            WIPE_CACHE_TOGGLE_ACTIONS = {
              toggle_wipe_cache_cached: :wipe_cache_cached,
              toggle_wipe_cache_downloads: :wipe_cache_downloads,
              toggle_wipe_cache_annotations: :wipe_cache_annotations,
              toggle_wipe_cache_bookmarks: :wipe_cache_bookmarks,
              toggle_wipe_cache_progress: :wipe_cache_progress,
              toggle_wipe_cache_config: :wipe_cache_config,
              toggle_wipe_cache_nuke: :wipe_cache_nuke,
            }.freeze

            def initialize(catalog_service = nil, dependencies: nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @config_reader = nil
            end

            def do_render(surface, bounds)
              frame = MenuDesign::FrameRenderer.new(surface, bounds)
              selected = menu_state_reader&.settings_selected || 1
              frame.render_title(title: 'Settings')
              frame.render_divider
              text_values = setting_value_map
              render_settings(surface, bounds, selected, text_values)
              frame.render_footer(text: footer_text(selected))
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
              line = "#{colors[:prefix]}#{colors[:fg]}#{label}#{colors[:suffix]}"
              line = "#{line}#{Shoko::Shared::Terminal::Ansi::RESET}  #{value_color}#{value_text}" if value_text && !value_text.to_s.empty?
              "#{line}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def row_colors(selected)
              if selected
                {
                  prefix: "#{Shoko::Shared::Terminal::Ansi::BOLD}#{MENU_SELECTION_BG}",
                  fg: MENU_SELECTION_TEXT,
                  suffix: ' ',
                }
              else
                { prefix: '', fg: COLOR_TEXT_PRIMARY, suffix: '' }
              end
            end

            def label_text(item)
              action = item.action
              if WIPE_CACHE_TOGGLE_ACTIONS.key?(action)
                checkbox = checkbox_glyph(wipe_cache_checked?(WIPE_CACHE_TOGGLE_ACTIONS[action]))
                "  #{checkbox}  #{item.label}"
              else
                icon = MenuDesign::IconSet.icon_for(item.icon_key)
                icon.empty? ? item.label : "#{icon}  #{item.label}"
              end
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
              indent = MenuDesign::Layout.centered_indent(bounds, content_width)
              content_rows = estimated_content_rows
              {
                indent: indent,
                start_row: MenuDesign::Layout.centered_row(bounds, top: 4, bottom: height - 3, content_rows: content_rows),
                max_row: height - 3,
              }
            end

            def display_width(text)
              Shoko::Shared::Terminal::TextMetrics.visible_length(text.to_s)
            end

            def setting_value_map
              {
                back_to_menu: ['Return to main menu', COLOR_TEXT_DIM],
                toggle_page_numbers: toggle_page_number_value,
                toggle_highlight_quotes: toggle_highlight_value,
                open_dictionary_settings: ['Configure & download dictionaries', COLOR_TEXT_DIM],
                toggle_kitty_images: toggle_kitty_images_value,
                wipe_cache: ['Use options below', COLOR_TEXT_WARNING],
              }
            end

            def render_button_group(surface, bounds, item, row, indent, selected, current_value, buttons)
              colors = row_colors(selected)
              label = "#{colors[:prefix]}#{colors[:fg]}#{label_text(item)}#{Shoko::Shared::Terminal::Ansi::RESET}"
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
              "#{bg}#{fg} #{label} #{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def button_group_width(buttons)
              buttons.sum do |_value, label|
                Shoko::Shared::Terminal::TextMetrics.visible_length(label) + 2
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
              config_reader&.view_mode || :single
            end

            def current_line_spacing
              config_reader&.line_spacing || :normal
            end

            def current_page_numbering_mode
              config_reader&.page_numbering_mode || :dynamic
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
              config_reader&.show_page_numbers ? 'Enabled' : 'Disabled'
            end

            def format_highlight_quotes
              value = config_reader&.highlight_quotes
              if value.nil? || !!value
                'On'
              else
                'Off'
              end
            end

            def toggle_kitty_images_value
              enabled = config_reader&.kitty_images == true
              text = enabled ? 'Enabled' : 'Disabled'
              color = enabled ? COLOR_TEXT_SUCCESS : COLOR_TEXT_DIM
              [text, color]
            end

            def menu_state_reader
              return @menu_state_reader if @menu_state_reader

              @menu_state_reader = @dependencies&.menu_state_reader
            end

            def checkbox_glyph(selected)
              if MenuDesign::IconSet.ascii_icons?
                selected ? '[x]' : '[ ]'
              else
                selected ? CHECKBOX_CHECKED : CHECKBOX_UNCHECKED
              end
            end

            def wipe_cache_checked?(key)
              reader = menu_state_reader
              return false unless reader

              case key
              when :wipe_cache_cached
                reader.wipe_cache_cached?
              when :wipe_cache_downloads
                reader.wipe_cache_downloads?
              when :wipe_cache_annotations
                reader.wipe_cache_annotations?
              when :wipe_cache_bookmarks
                reader.wipe_cache_bookmarks?
              when :wipe_cache_progress
                reader.wipe_cache_progress?
              when :wipe_cache_config
                reader.wipe_cache_config?
              when :wipe_cache_nuke
                reader.wipe_cache_nuke?
              else
                false
              end
            rescue Shoko::Error
              raise
            end

            def config_reader
              return @config_reader if @config_reader

              @config_reader = @dependencies&.config_reader
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

            def footer_text(selected_index)
              item = SETTINGS_ITEMS[selected_index.to_i] || SETTINGS_ITEMS.first
              item ? item.label : 'Settings'
            end
          end
        end
      end
    end
  end
end
