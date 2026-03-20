# frozen_string_literal: true

module Shoko
  module Shared
    # Canonical menu descriptors used by UI rendering and input routing.
    module MenuDefinitions
      MainMenuItem = Data.define(:key, :label, :icon_key, :action)
      SettingsItem = Data.define(:action, :label, :icon_key)
      DictionaryActionItem = Data.define(:key, :label, :value_key, :action)

      MAIN_MENU_ITEMS = [
        MainMenuItem.new(key: :browse, label: 'Browse Library', icon_key: :browse, action: :switch_to_browse),
        MainMenuItem.new(key: :library, label: 'Library', icon_key: :library, action: :switch_to_library),
        MainMenuItem.new(key: :annotations,
                         label: 'Annotations',
                         icon_key: :annotations,
                         action: :switch_to_annotations),
        MainMenuItem.new(key: :download, label: 'Download Books', icon_key: :download, action: :open_download),
        MainMenuItem.new(key: :settings, label: 'Settings', icon_key: :settings, action: :switch_to_settings),
        MainMenuItem.new(key: :quit, label: 'Quit', icon_key: :quit, action: :quit),
      ].freeze

      SETTINGS_ITEMS = [
        SettingsItem.new(action: :back_to_menu, icon_key: :back, label: 'Go Back'),
        SettingsItem.new(action: :toggle_view_mode, icon_key: :view_mode, label: 'View Mode'),
        SettingsItem.new(action: :cycle_line_spacing, icon_key: :line_spacing, label: 'Line Spacing'),
        SettingsItem.new(action: :cycle_download_source, icon_key: :download, label: 'Download Source'),
        SettingsItem.new(action: :cycle_theme, icon_key: :theme, label: 'Theme'),
        SettingsItem.new(action: :toggle_page_numbering_mode, icon_key: :page_mode, label: 'Page Numbering Mode'),
        SettingsItem.new(action: :toggle_page_numbers, icon_key: :page_numbers, label: 'Page Numbers'),
        SettingsItem.new(action: :toggle_highlight_quotes, icon_key: :highlight, label: 'Text Highlighting'),
        SettingsItem.new(action: :open_dictionary_settings, icon_key: :dictionary, label: 'Dictionary'),
        SettingsItem.new(action: :toggle_kitty_images, icon_key: :images, label: 'Inline Images'),
        SettingsItem.new(action: :wipe_cache, icon_key: :wipe, label: 'Wipe Cache'),
        SettingsItem.new(action: :toggle_wipe_cache_cached, icon_key: :checkbox, label: 'Cached data'),
        SettingsItem.new(action: :toggle_wipe_cache_downloads, icon_key: :checkbox, label: 'Downloaded books'),
        SettingsItem.new(action: :toggle_wipe_cache_annotations, icon_key: :checkbox, label: 'Annotations'),
        SettingsItem.new(action: :toggle_wipe_cache_bookmarks, icon_key: :checkbox, label: 'Bookmarks'),
        SettingsItem.new(action: :toggle_wipe_cache_progress, icon_key: :checkbox, label: 'Progress'),
        SettingsItem.new(action: :toggle_wipe_cache_config, icon_key: :checkbox, label: 'Config'),
        SettingsItem.new(action: :toggle_wipe_cache_nuke, icon_key: :checkbox, label: 'Nuke everything'),
      ].freeze

      DICTIONARY_ACTION_ITEMS = [
        DictionaryActionItem.new(key: :back, label: 'Back', value_key: :back_value, action: :dictionary_back),
        DictionaryActionItem.new(key: :toggle_lookup,
                                 label: 'Lookup',
                                 value_key: :lookup_value,
                                 action: :toggle_dictionary_backend),
        DictionaryActionItem.new(key: :pair, label: 'Pair', value_key: :pair_value, action: :cycle_dictionary_pair),
        DictionaryActionItem.new(key: :storage, label: 'Storage', value_key: :storage_value, action: nil),
        DictionaryActionItem.new(key: :refresh,
                                 label: 'Refresh Catalog',
                                 value_key: :refresh_value,
                                 action: :dictionary_refresh),
      ].freeze

      module_function

      def main_menu_items
        MAIN_MENU_ITEMS
      end

      def main_menu_item(index)
        MAIN_MENU_ITEMS[index]
      end

      def settings_items
        SETTINGS_ITEMS
      end

      def settings_actions
        SETTINGS_ITEMS.map(&:action)
      end

      def dictionary_action_items
        DICTIONARY_ACTION_ITEMS
      end

      def dictionary_action_item(index)
        DICTIONARY_ACTION_ITEMS[index]
      end
    end
  end
end
