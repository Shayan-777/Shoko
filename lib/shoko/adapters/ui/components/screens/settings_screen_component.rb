# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../constants/themes'
require_relative '../../../../shared/menu_definitions'
require_relative '../../../../shared/download_source_policy'
require_relative '../../../../shared/theme_policy'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/table_renderer'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Settings screen component with a unified list + inspector layout.
          class SettingsScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils

            SETTINGS_ITEMS = Shoko::Shared::MenuDefinitions.settings_items

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
            SETTING_DETAILS = {
              back_to_menu: {
                description: 'Return to the main menu.',
                controls: 'Enter or Space returns immediately.',
              },
              toggle_view_mode: {
                description: 'Choose whether the reader shows one page or a two-page spread.',
                controls: 'Enter or Space toggles the mode.',
                options: %w[Single Split],
              },
              cycle_line_spacing: {
                description: 'Control how dense the reading layout feels.',
                controls: 'Enter or Space cycles the spacing.',
                options: %w[Normal Relaxed Compact],
              },
              cycle_download_source: {
                description: 'Select which remote catalog powers the download screen.',
                controls: 'Enter or Space cycles the source.',
                options: %w[Gutendex Libgen],
              },
              cycle_theme: {
                description: 'Change the palette used across menus and reading surfaces.',
                controls: 'Enter or Space advances to the next theme.',
              },
              toggle_page_numbering_mode: {
                description: 'Choose between absolute document pages and dynamic paginated pages.',
                controls: 'Enter or Space toggles the mode.',
                options: %w[Absolute Dynamic],
              },
              toggle_page_numbers: {
                description: 'Show or hide page numbers in the reader footer.',
                controls: 'Enter or Space toggles page numbers.',
              },
              toggle_highlight_quotes: {
                description: 'Emphasize quoted passages while rendering text.',
                controls: 'Enter or Space toggles quote highlighting.',
              },
              open_dictionary_settings: {
                description: 'Open dictionary catalog, download, and lookup settings.',
                controls: 'Enter or Space opens dictionary settings.',
              },
              toggle_kitty_images: {
                description: 'Enable inline images when Kitty graphics are supported.',
                controls: 'Enter or Space toggles image rendering.',
              },
              wipe_cache: {
                description: 'Delete cached data using the flags listed below. Review carefully before running.',
                controls: 'Enter or Space executes the wipe.',
              },
              toggle_wipe_cache_cached: {
                description: 'Include cached payloads and pagination data in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_downloads: {
                description: 'Include downloaded books in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_annotations: {
                description: 'Include saved annotations in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_bookmarks: {
                description: 'Include saved bookmarks in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_progress: {
                description: 'Include reading progress snapshots in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_config: {
                description: 'Include the saved configuration file in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_nuke: {
                description: 'Arm a full reset. This enables every wipe flag at once.',
                controls: 'Enter or Space toggles the nuke flag.',
              },
            }.freeze
            EMPTY_SETTING_DETAIL = {}.freeze

            def initialize(catalog_service = nil, dependencies: nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @config_reader = nil
            end

            def do_render(surface, bounds)
              shell = MenuDesign::MasterDetailShell.new(surface, bounds)
              layout = shell.build_layout(
                detail_visible: true,
                desired_detail_width: 34,
                min_primary_width: 36,
                min_detail_width: 28,
                stacked_detail_height: 10
              )
              selected = selected_index
              item = SETTINGS_ITEMS[selected] || SETTINGS_ITEMS.first
              value_text, value_color = display_value_for(item.action)

              shell.render_frame(
                layout: layout,
                title: 'Settings',
                hint: 'ENTER apply  SPACE apply  ESC back',
                summary_left: 'J/K move',
                summary_right: value_text,
                summary_right_color: value_color,
                footer: footer_text(selected)
              )
              shell.render_panels(
                layout: layout,
                primary_title: 'Preferences',
                secondary_title: 'Selection'
              )
              render_settings_list(surface, bounds, layout.primary_panel.content, selected)
              render_selection_details(surface, bounds, layout.secondary_panel&.content, item, value_text, value_color)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def render_settings_list(surface, bounds, panel, selected)
              columns = list_columns(panel.width)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: %w[Setting Value],
                widths: [columns[:label], columns[:value]],
                divider_char: '─'
              )

              visible_rows = [panel.height - 2, 0].max
              return if visible_rows <= 0

              start_index, visible = Ui::ListHelpers.slice_visible(SETTINGS_ITEMS, visible_rows, selected)
              current_row = panel.y + 2
              visible.each_with_index do |item, offset|
                break if current_row > panel.bottom

                absolute_index = start_index + offset
                value_text, = display_value_for(item.action)
                MenuDesign::TableRenderer.new(surface, bounds).render_row(
                  row: current_row,
                  indent: panel.x,
                  cells: [
                    pad_right(truncate_text(label_text(item), columns[:label]), columns[:label]),
                    pad_right(truncate_text(value_text, columns[:value]), columns[:value]),
                  ],
                  widths: [columns[:label], columns[:value]],
                  selected: absolute_index == selected
                )
                current_row += 1
              end
            end

            def render_selection_details(surface, bounds, panel, item, value_text, value_color)
              return unless panel && item

              detail = SETTING_DETAILS.fetch(item.action, EMPTY_SETTING_DETAIL)
              row = panel.y
              row = render_selection_title(surface, bounds, panel, row, item.label)
              row = render_current_value(surface, bounds, panel, row, value_text, value_color)
              row = write_wrapped_block(surface, bounds, panel, row, detail.fetch(:description, ''), COLOR_TEXT_PRIMARY)
              row = render_options_detail(surface, bounds, panel, row, detail[:options])
              render_controls_detail(surface, bounds, panel, row, detail[:controls])
            end

            def render_selection_title(surface, bounds, panel, row, title)
              wrap_text(title.to_s, panel.width).each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, selection_title_text(line))
                row += 1
              end
              row
            end

            def render_current_value(surface, bounds, panel, row, value_text, value_color)
              return row if row > panel.bottom

              surface.write(bounds, row, panel.x, dim_text('Current'))
              row += 1
              return row if row > panel.bottom

              surface.write(bounds, row, panel.x, colorized_text(value_color, value_text))
              row + 2
            end

            def render_options_detail(surface, bounds, panel, row, options)
              return row unless options && row <= panel.bottom

              row += 1
              row = write_label(surface, bounds, panel, row, 'Options')
              write_wrapped_block(surface, bounds, panel, row, Array(options).join(' • '), COLOR_TEXT_DIM)
            end

            def render_controls_detail(surface, bounds, panel, row, controls)
              return row unless controls && row <= panel.bottom

              row += 1
              row = write_label(surface, bounds, panel, row, 'Controls')
              write_wrapped_block(surface, bounds, panel, row, controls, COLOR_TEXT_DIM)
            end

            def write_label(surface, bounds, panel, row, text)
              return row if row > panel.bottom

              surface.write(bounds, row, panel.x, dim_text(text.upcase))
              row + 1
            end

            def write_wrapped_block(surface, bounds, panel, row, text, color)
              wrap_text(text.to_s, panel.width).each do |line|
                break if row > panel.bottom

                surface.write(bounds, row, panel.x, "#{color}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
              row
            end

            def list_columns(width)
              gap = 3
              value_width = (width / 3).clamp(12, 18)
              label_width = [width - value_width - gap, 18].max
              { label: label_width, value: value_width }
            end

            def selected_index
              current = (menu_state_reader&.settings_selected || 1).to_i
              current.clamp(0, SETTINGS_ITEMS.length - 1)
            end

            def display_value_for(action)
              static_value_for(action) || preference_value_for(action) || wipe_cache_toggle_value(action) || ['—', COLOR_TEXT_DIM]
            end

            def bool_value(raw, default_truthy, true_text:, false_text:)
              enabled = raw.nil? ? default_truthy : raw == true
              [enabled ? true_text : false_text, enabled ? COLOR_TEXT_SUCCESS : COLOR_TEXT_WARNING]
            end

            def label_text(item)
              action = item.action
              if WIPE_CACHE_TOGGLE_ACTIONS.key?(action)
                "#{checkbox_glyph(wipe_cache_checked?(WIPE_CACHE_TOGGLE_ACTIONS[action]))} #{item.label}"
              else
                item.label
              end
            end

            def humanize_symbol(value)
              value.to_s.split('_').map(&:capitalize).join(' ')
            end

            def humanize_theme(theme_id)
              humanize_symbol(theme_id)
            end

            def static_value_for(action)
              case action
              when :back_to_menu
                ['Return', COLOR_TEXT_DIM]
              when :open_dictionary_settings
                ['Open', COLOR_TEXT_DIM]
              when :wipe_cache
                ['Run', COLOR_TEXT_WARNING]
              end
            end

            def preference_value_for(action)
              case action
              when :toggle_view_mode
                accent_value(humanize_symbol(current_view_mode))
              when :cycle_line_spacing
                accent_value(humanize_symbol(current_line_spacing))
              when :cycle_download_source
                accent_value(Shoko::Shared::DownloadSourcePolicy.label_for(current_download_source))
              when :cycle_theme
                accent_value(humanize_theme(current_theme_id))
              when :toggle_page_numbering_mode
                accent_value(humanize_symbol(current_page_numbering_mode))
              when :toggle_page_numbers
                bool_value(config_reader&.show_page_numbers, true, true_text: 'Enabled', false_text: 'Disabled')
              when :toggle_highlight_quotes
                bool_value(config_reader&.highlight_quotes, true, true_text: 'On', false_text: 'Off')
              when :toggle_kitty_images
                bool_value(config_reader&.kitty_images, false, true_text: 'Enabled', false_text: 'Disabled')
              end
            end

            def accent_value(text)
              [text, COLOR_TEXT_ACCENT]
            end

            def wipe_cache_toggle_value(action)
              return nil unless WIPE_CACHE_TOGGLE_ACTIONS.key?(action)

              armed = wipe_cache_checked?(WIPE_CACHE_TOGGLE_ACTIONS.fetch(action))
              [armed ? 'Armed' : 'Off', armed ? COLOR_TEXT_WARNING : COLOR_TEXT_DIM]
            end

            def selection_title_text(text)
              colorized_text(
                "#{Shoko::Shared::Terminal::Ansi::BOLD}#{COLOR_TEXT_ACCENT}",
                text
              )
            end

            def dim_text(text)
              colorized_text(COLOR_TEXT_DIM, text)
            end

            def colorized_text(color, text)
              "#{color}#{text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def current_theme_id
              Shoko::Shared::ThemePolicy.normalize(config_reader&.theme) || Shoko::Shared::ThemePolicy.default_id
            end

            def current_view_mode
              config_reader&.view_mode || :single
            end

            def current_line_spacing
              config_reader&.line_spacing || :normal
            end

            def current_download_source
              Shoko::Shared::DownloadSourcePolicy.normalize(config_reader&.download_source) ||
                Shoko::Shared::DownloadSourcePolicy.default_id
            end

            def current_page_numbering_mode
              config_reader&.page_numbering_mode || :dynamic
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
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
            end

            def config_reader
              @config_reader ||= @dependencies&.config_reader
            end

            def footer_text(selected_index)
              item = SETTINGS_ITEMS[selected_index] || SETTINGS_ITEMS.first
              item ? item.label : 'Settings'
            end
          end
        end
      end
    end
  end
end
