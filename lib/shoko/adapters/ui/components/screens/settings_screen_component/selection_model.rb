# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          module SettingsScreenComponentSelectionModel
            private

            def selected_index
              current = (menu_state_reader&.settings_selected || 1).to_i
              current.clamp(0, SettingsScreenComponent::SETTINGS_ITEMS.length - 1)
            end

            def label_text(item)
              action = item.action
              if SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS.key?(action)
                "#{checkbox_glyph(wipe_cache_checked?(SettingsScreenComponent::WIPE_CACHE_TOGGLE_ACTIONS[action]))} #{item.label}"
              else
                item.label
              end
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

            def footer_text(current_index)
              item = SettingsScreenComponent::SETTINGS_ITEMS[current_index] || SettingsScreenComponent::SETTINGS_ITEMS.first
              item ? item.label : 'Settings'
            end
          end
        end
      end
    end
  end
end
