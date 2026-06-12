# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../constants/themes'
require_relative '../../../../application/ports/inbound/menu_catalog'
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

            SETTINGS_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.settings_items

            CHECKBOX_UNCHECKED = '󰄱'
            CHECKBOX_CHECKED = '󰱒'
            WIPE_CACHE_TOGGLE_ACTIONS = {
              toggle_wipe_cache_cached: :wipe_cache_cached,
              toggle_wipe_cache_downloads: :wipe_cache_downloads,
              toggle_wipe_cache_dictionary: :wipe_cache_dictionary,
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
              toggle_prepaginate_on_resize: {
                description: 'On startup, pre-paginate cached books in the background after the terminal ' \
                             'size changes, so opening any book is instant. Off by default — leave off to ' \
                             'recalculate each book only when you open it.',
                controls: 'Enter or Space toggles pre-pagination.',
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
              toggle_wipe_cache_dictionary: {
                description: 'Include downloaded dictionaries in the wipe. Left off (and excluded from Nuke) ' \
                             'so they survive a wipe instead of being re-downloaded.',
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
                description: 'Arm a full reset. This enables every wipe flag except Dictionaries, ' \
                             'which stays under its own toggle so downloads survive.',
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
              layout = build_shell_layout(shell)
              selection = selected_setting_payload

              render_settings_shell(shell, layout, selection)
              render_settings_list(surface, bounds, layout.primary_panel.content, selection[:index])
              render_selection_details(panel_context(surface, bounds, layout.secondary_panel&.content), selection)
            end

            def preferred_height(_available_height)
              :fill
            end

            SettingRow = Data.define(:row, :item, :selected, :columns, :indent)

            PREFERENCE_VALUE_HELPERS = {
              toggle_view_mode: :view_mode_value,
              cycle_line_spacing: :line_spacing_value,
              cycle_download_source: :download_source_value,
              cycle_theme: :theme_value,
              toggle_page_numbering_mode: :page_numbering_mode_value,
              toggle_page_numbers: :page_numbers_value,
              toggle_highlight_quotes: :highlight_quotes_value,
              toggle_kitty_images: :kitty_images_value,
              toggle_prepaginate_on_resize: :prepaginate_on_resize_value,
            }.freeze

            private

            def build_shell_layout(shell)
              shell.build_layout(
                detail_visible: true,
                desired_detail_width: 34,
                min_primary_width: 36,
                min_detail_width: 28,
                stacked_detail_height: 10
              )
            end

            def selected_setting_payload
              index = selected_index
              item = SETTINGS_ITEMS[index] || SETTINGS_ITEMS.first
              value_text, value_color = display_value_for(item.action)
              { index: index, item: item, value_text: value_text, value_color: value_color }
            end

            def render_settings_shell(shell, layout, selection)
              shell.render_frame(
                layout: layout,
                title: 'Settings',
                hint: 'ENTER apply  SPACE apply  ESC back',
                summary_left: 'J/K move',
                summary_right: selection[:value_text],
                summary_right_color: selection[:value_color],
                footer: footer_text(selection[:index])
              )
              shell.render_panels(layout: layout, primary_title: 'Preferences', secondary_title: 'Selection')
            end

            def panel_context(surface, bounds, panel)
              { surface: surface, bounds: bounds, panel: panel }
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def config_reader
              @config_reader ||= @dependencies&.config_reader
            end

            def render_selection_details(context, selection)
              panel = context[:panel]
              item = selection[:item]
              return unless panel && item

              detail = selection_detail(item.action)
              row = panel.y
              row = render_selection_title(context, row, item.label)
              row = render_current_value(context, row, selection[:value_text], selection[:value_color])
              row = write_wrapped_block(context, row, detail.fetch(:description, ''), self.class::COLOR_TEXT_PRIMARY)
              row = render_options_detail(context, row, detail[:options])
              render_controls_detail(context, row, detail[:controls])
            end

            def selection_detail(action)
              SettingsScreenComponent::SETTING_DETAILS.fetch(action, SettingsScreenComponent::EMPTY_SETTING_DETAIL)
            end

            def render_selection_title(context, row, title)
              panel = context[:panel]
              wrap_text(title.to_s, panel.width).each do |line|
                break if row > panel.bottom

                write_detail_text(context, row, selection_title_text(line))
                row += 1
              end
              row
            end

            def render_current_value(context, row, value_text, value_color)
              panel = context[:panel]
              return row if row > panel.bottom

              write_detail_text(context, row, dim_text('Current'))
              row += 1
              return row if row > panel.bottom

              write_detail_text(context, row, colorized_text(value_color, value_text))
              row + 2
            end

            def render_options_detail(context, row, options)
              panel = context[:panel]
              return row unless options && row <= panel.bottom

              row += 1
              row = write_label(context, row, 'Options')
              write_wrapped_block(context, row, Array(options).join(' • '), self.class::COLOR_TEXT_DIM)
            end

            def render_controls_detail(context, row, controls)
              panel = context[:panel]
              return row unless controls && row <= panel.bottom

              row += 1
              row = write_label(context, row, 'Controls')
              write_wrapped_block(context, row, controls, self.class::COLOR_TEXT_DIM)
            end

            def write_label(context, row, text)
              panel = context[:panel]
              return row if row > panel.bottom

              write_detail_text(context, row, dim_text(text.upcase))
              row + 1
            end

            def write_wrapped_block(context, row, text, color)
              panel = context[:panel]
              wrap_text(text.to_s, panel.width).each do |line|
                break if row > panel.bottom

                write_detail_text(context, row, "#{color}#{line}#{Shoko::Shared::Terminal::Ansi::RESET}")
                row += 1
              end
              row
            end

            def write_detail_text(context, row, text)
              panel = context[:panel]
              context[:surface].write(context[:bounds], row, panel.x, text)
            end

            def selection_title_text(text)
              colorized_text("#{Shoko::Shared::Terminal::Ansi::BOLD}#{self.class::COLOR_TEXT_ACCENT}", text)
            end

            def dim_text(text)
              colorized_text(self.class::COLOR_TEXT_DIM, text)
            end

            def colorized_text(color, text)
              "#{color}#{text}#{Shoko::Shared::Terminal::Ansi::RESET}"
            end

            def render_settings_list(surface, bounds, panel, selected)
              columns = list_columns(panel.width)
              render_settings_header(surface, bounds, panel, columns)

              setting_rows(panel, selected, columns).each do |row|
                render_settings_row(surface, bounds, row)
              end
            end

            def render_settings_header(surface, bounds, panel, columns)
              MenuDesign::TableRenderer.new(surface, bounds).render_header(
                row: panel.y,
                indent: panel.x,
                headers: %w[Setting Value],
                widths: [columns[:label], columns[:value]],
                divider_char: '─'
              )
            end

            def setting_rows(panel, selected, columns)
              visible_rows = [panel.height - 2, 0].max
              return [] if visible_rows <= 0

              slice = visible_setting_slice(selected, visible_rows)
              slice[:items].each_with_index.filter_map do |item, offset|
                build_setting_row(panel: panel,
                                  columns: columns,
                                  selected: selected,
                                  item: item,
                                  offset: offset,
                                  start_index: slice[:start_index])
              end
            end

            def build_setting_row(panel:, columns:, selected:, start_index:, item:, offset:)
              row = panel.y + 2 + offset
              return nil if row > panel.bottom

              SettingRow.new(
                row: row,
                item: item,
                selected: (start_index + offset) == selected,
                columns: columns,
                indent: panel.x
              )
            end

            def visible_setting_slice(selected, visible_rows)
              start_index, items = Ui::ListHelpers.slice_visible(
                SettingsScreenComponent::SETTINGS_ITEMS,
                visible_rows,
                selected
              )
              { start_index: start_index, items: items }
            end

            def render_settings_row(surface, bounds, row)
              value_text, = display_value_for(row.item.action)
              MenuDesign::TableRenderer.new(surface, bounds).render_row(
                row: row.row,
                indent: row.indent,
                cells: setting_row_cells(row, value_text),
                widths: [row.columns[:label], row.columns[:value]],
                selected: row.selected
              )
            end

            def setting_row_cells(row, value_text)
              [
                pad_right(truncate_text(label_text(row.item), row.columns[:label]), row.columns[:label]),
                pad_right(truncate_text(value_text, row.columns[:value]), row.columns[:value]),
              ]
            end

            def list_columns(width)
              gap = 3
              value_width = (width / 3).clamp(12, 18)
              { label: [width - value_width - gap, 18].max, value: value_width }
            end

            def selected_index
              current = (menu_state_reader&.settings_selected || 1).to_i
              current.clamp(0, SettingsScreenComponent::SETTINGS_ITEMS.length - 1)
            end

            def label_text(item)
              action = item.action
              wipe_key = SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS[action]
              return item.label unless wipe_key

              "#{checkbox_glyph(wipe_cache_checked?(wipe_key))} #{item.label}"
            end

            def checkbox_glyph(selected)
              if MenuDesign::IconSet.ascii_icons?
                selected ? '[x]' : '[ ]'
              else
                selected ? SettingsScreenComponent::CHECKBOX_CHECKED : SettingsScreenComponent::CHECKBOX_UNCHECKED
              end
            end

            def wipe_cache_checked?(key)
              reader = menu_state_reader
              return false unless reader

              predicate = "#{key}?"
              reader.respond_to?(predicate) && reader.public_send(predicate)
            end

            def footer_text(current_index)
              item = SettingsScreenComponent::SETTINGS_ITEMS[current_index] || SettingsScreenComponent::SETTINGS_ITEMS.first
              item ? item.label : 'Settings'
            end

            def display_value_for(action)
              static_value_for(action) ||
                preference_value_for(action) ||
                wipe_cache_toggle_value(action) ||
                default_display_value
            end

            def bool_value(raw, default_truthy, true_text:, false_text:)
              enabled = raw.nil? ? default_truthy : raw == true
              [enabled ? true_text : false_text,
               enabled ? self.class::COLOR_TEXT_SUCCESS : self.class::COLOR_TEXT_WARNING]
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
                ['Return', self.class::COLOR_TEXT_DIM]
              when :open_dictionary_settings
                ['Open', self.class::COLOR_TEXT_DIM]
              when :wipe_cache
                ['Run', self.class::COLOR_TEXT_WARNING]
              end
            end

            def preference_value_for(action)
              helper = PREFERENCE_VALUE_HELPERS[action]
              helper && send(helper)
            end

            def accent_value(text)
              [text, self.class::COLOR_TEXT_ACCENT]
            end

            def default_display_value
              ['—', self.class::COLOR_TEXT_DIM]
            end

            def wipe_cache_toggle_value(action)
              return nil unless SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS.key?(action)

              armed = wipe_cache_checked?(SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS.fetch(action))
              [armed ? 'Armed' : 'Off', armed ? self.class::COLOR_TEXT_WARNING : self.class::COLOR_TEXT_DIM]
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

            def view_mode_value
              accent_value(humanize_symbol(current_view_mode))
            end

            def line_spacing_value
              accent_value(humanize_symbol(current_line_spacing))
            end

            def download_source_value
              accent_value(Shoko::Shared::DownloadSourcePolicy.label_for(current_download_source))
            end

            def theme_value
              accent_value(humanize_theme(current_theme_id))
            end

            def page_numbering_mode_value
              accent_value(humanize_symbol(current_page_numbering_mode))
            end

            def page_numbers_value
              bool_value(config_reader&.show_page_numbers, true, true_text: 'Enabled', false_text: 'Disabled')
            end

            def highlight_quotes_value
              bool_value(config_reader&.highlight_quotes, true, true_text: 'On', false_text: 'Off')
            end

            def kitty_images_value
              bool_value(config_reader&.kitty_images, false, true_text: 'Enabled', false_text: 'Disabled')
            end

            def prepaginate_on_resize_value
              bool_value(config_reader&.prepaginate_on_resize, false, true_text: 'On', false_text: 'Off')
            end
          end
        end
      end
    end
  end
end
