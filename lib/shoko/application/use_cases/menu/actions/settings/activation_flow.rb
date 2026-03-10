# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Settings
            module ActivationFlow
              private

              def activate_settings_selection
                action = self.class::SETTINGS_ACTIONS[(@menu_state_reader.settings_selected || 0).to_i]
                return :pass unless action

                case action
                when :back_to_menu
                  @navigation_actions.call(:switch_to_menu_mode)
                when :toggle_view_mode
                  @settings_service.toggle_view_mode
                when :cycle_line_spacing
                  @settings_service.cycle_line_spacing
                when :cycle_theme
                  @settings_service.cycle_theme
                when :toggle_page_numbering_mode
                  @settings_service.toggle_page_numbering_mode
                when :toggle_page_numbers
                  @settings_service.toggle_page_numbers
                when :toggle_highlight_quotes
                  @settings_service.toggle_highlight_quotes
                when :open_dictionary_settings
                  @dictionary_actions.call(:open_dictionary_mode)
                when :toggle_kitty_images
                  @settings_service.toggle_kitty_images
                when :wipe_cache
                  wipe_cache
                when :toggle_wipe_cache_cached
                  toggle_wipe_cache_flag(:wipe_cache_cached, default: true)
                when :toggle_wipe_cache_downloads
                  toggle_wipe_cache_flag(:wipe_cache_downloads, default: false)
                when :toggle_wipe_cache_annotations
                  toggle_wipe_cache_flag(:wipe_cache_annotations, default: false)
                when :toggle_wipe_cache_bookmarks
                  toggle_wipe_cache_flag(:wipe_cache_bookmarks, default: false)
                when :toggle_wipe_cache_progress
                  toggle_wipe_cache_flag(:wipe_cache_progress, default: false)
                when :toggle_wipe_cache_config
                  toggle_wipe_cache_flag(:wipe_cache_config, default: false)
                when :toggle_wipe_cache_nuke
                  toggle_wipe_cache_nuke
                else
                  :pass
                end

                :handled
              end

              def wipe_cache
                @settings_service.wipe_cache(
                  catalog: @catalog,
                  cached: @menu_state_reader.wipe_cache_cached? || nil,
                  downloads: @menu_state_reader.wipe_cache_downloads? || nil,
                  nuke: @menu_state_reader.wipe_cache_nuke? || nil,
                  annotations: @menu_state_reader.wipe_cache_annotations? || nil,
                  bookmarks: @menu_state_reader.wipe_cache_bookmarks? || nil,
                  progress: @menu_state_reader.wipe_cache_progress? || nil,
                  config_file: @menu_state_reader.wipe_cache_config? || nil
                )
              end

              def toggle_wipe_cache_flag(key, default:)
                current = read_wipe_cache_flag(key, default: default)
                payload = { key => !current }
                payload[:wipe_cache_nuke] = false if current == false && @menu_state_reader.wipe_cache_nuke?
                @menu_session_mutator.update_menu(payload)
              end

              def toggle_wipe_cache_nuke
                new_value = !@menu_state_reader.wipe_cache_nuke?
                payload = { wipe_cache_nuke: new_value }

                if new_value
                  payload[:wipe_cache_cached] = true
                  payload[:wipe_cache_downloads] = true
                  payload[:wipe_cache_annotations] = true
                  payload[:wipe_cache_bookmarks] = true
                  payload[:wipe_cache_progress] = true
                  payload[:wipe_cache_config] = true
                end

                @menu_session_mutator.update_menu(payload)
              end

              def read_wipe_cache_flag(key, default:)
                case key
                when :wipe_cache_cached then @menu_state_reader.wipe_cache_cached?
                when :wipe_cache_downloads then @menu_state_reader.wipe_cache_downloads?
                when :wipe_cache_annotations then @menu_state_reader.wipe_cache_annotations?
                when :wipe_cache_bookmarks then @menu_state_reader.wipe_cache_bookmarks?
                when :wipe_cache_progress then @menu_state_reader.wipe_cache_progress?
                when :wipe_cache_config then @menu_state_reader.wipe_cache_config?
                else
                  default
                end
              end
            end
          end
        end
      end
    end
  end
end
