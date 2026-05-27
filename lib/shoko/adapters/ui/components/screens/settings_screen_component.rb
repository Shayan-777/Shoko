# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../constants/themes'
require_relative '../../../../application/ports/inbound/menu_catalog'
require_relative '../../../../shared/download_source_policy'
require_relative '../../../../shared/theme_policy'
require_relative 'settings_screen_component/detail_renderer'
require_relative 'settings_screen_component/list_renderer'
require_relative 'settings_screen_component/selection_model'
require_relative 'settings_screen_component/value_resolver'
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
            include SettingsScreenComponentDetailRenderer
            include SettingsScreenComponentListRenderer
            include SettingsScreenComponentSelectionModel
            include SettingsScreenComponentValueResolver

            SETTINGS_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.settings_items

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
              layout = build_shell_layout(shell)
              selection = selected_setting_payload

              render_settings_shell(shell, layout, selection)
              render_settings_list(surface, bounds, layout.primary_panel.content, selection[:index])
              render_selection_details(panel_context(surface, bounds, layout.secondary_panel&.content), selection)
            end

            def preferred_height(_available_height)
              :fill
            end

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
          end
        end
      end
    end
  end
end
