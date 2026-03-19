# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Selection-state helpers and wipe-cache checkbox presentation.
          module SettingsScreenComponentSelectionModel
            private

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
          end
        end
      end
    end
  end
end
