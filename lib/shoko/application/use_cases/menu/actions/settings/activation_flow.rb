# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Settings
            # Applies the selected settings action to the active menu state.
            module ActivationFlow
              SETTINGS_SERVICE_ACTIONS = {
                toggle_view_mode: lambda(&:toggle_view_mode),
                cycle_line_spacing: lambda(&:cycle_line_spacing),
                cycle_download_source: lambda(&:cycle_download_source),
                cycle_theme: lambda(&:cycle_theme),
                toggle_page_numbering_mode: lambda(&:toggle_page_numbering_mode),
                toggle_page_numbers: lambda(&:toggle_page_numbers),
                toggle_highlight_quotes: lambda(&:toggle_highlight_quotes),
                toggle_kitty_images: lambda(&:toggle_kitty_images),
              }.freeze
              WIPE_CACHE_FLAG_ACTIONS = {
                toggle_wipe_cache_cached: { key: :wipe_cache_cached, default: true },
                toggle_wipe_cache_downloads: { key: :wipe_cache_downloads, default: false },
                toggle_wipe_cache_annotations: { key: :wipe_cache_annotations, default: false },
                toggle_wipe_cache_bookmarks: { key: :wipe_cache_bookmarks, default: false },
                toggle_wipe_cache_progress: { key: :wipe_cache_progress, default: false },
                toggle_wipe_cache_config: { key: :wipe_cache_config, default: false },
              }.freeze

              private

              def activate_settings_selection
                action = selected_settings_action
                return :pass unless action

                dispatch_settings_action(action)
              end

              def selected_settings_action
                self.class::SETTINGS_ACTIONS[(current_menu.settings_selected || 0).to_i]
              end

              def dispatch_settings_action(action)
                service_result = dispatch_settings_service_action(action)
                return service_result unless service_result == :pass
                return dispatch_wipe_cache_flag_action(action) if wipe_cache_flag_action?(action)

                dispatch_special_settings_action(action)
              end

              def dispatch_special_settings_action(action)
                case action
                when :back_to_menu
                  @navigation_actions.call(:switch_to_menu_mode)
                when :open_dictionary_settings
                  @dictionary_actions.call(:open_dictionary_mode)
                when :wipe_cache
                  wipe_cache
                when :toggle_wipe_cache_nuke
                  toggle_wipe_cache_nuke
                else
                  return :pass
                end
                :handled
              end

              def dispatch_settings_service_action(action)
                handler = self.class::SETTINGS_SERVICE_ACTIONS[action]
                return :pass unless handler

                handler.call(@settings_service)
                :handled
              end

              def wipe_cache_flag_action?(action)
                self.class::WIPE_CACHE_FLAG_ACTIONS.key?(action)
              end

              def dispatch_wipe_cache_flag_action(action)
                config = self.class::WIPE_CACHE_FLAG_ACTIONS.fetch(action)
                toggle_wipe_cache_flag(config.fetch(:key), default: config.fetch(:default))
                :handled
              end

              def wipe_cache
                menu = current_menu
                @settings_service.wipe_cache(
                  catalog: @catalog,
                  cached: menu.wipe_cache_cached? || nil,
                  downloads: menu.wipe_cache_downloads? || nil,
                  nuke: menu.wipe_cache_nuke? || nil,
                  annotations: menu.wipe_cache_annotations? || nil,
                  bookmarks: menu.wipe_cache_bookmarks? || nil,
                  progress: menu.wipe_cache_progress? || nil,
                  config_file: menu.wipe_cache_config? || nil
                )
              end

              def toggle_wipe_cache_flag(key, default:)
                current = read_wipe_cache_flag(key, default: default)
                payload = { key => !current }
                payload[:wipe_cache_nuke] = false if current == false && current_menu.wipe_cache_nuke?
                update_menu(payload)
              end

              def toggle_wipe_cache_nuke
                new_value = !current_menu.wipe_cache_nuke?
                payload = { wipe_cache_nuke: new_value }

                if new_value
                  payload[:wipe_cache_cached] = true
                  payload[:wipe_cache_downloads] = true
                  payload[:wipe_cache_annotations] = true
                  payload[:wipe_cache_bookmarks] = true
                  payload[:wipe_cache_progress] = true
                  payload[:wipe_cache_config] = true
                end

                update_menu(payload)
              end

              def read_wipe_cache_flag(key, default:)
                menu = current_menu
                case key
                when :wipe_cache_cached then menu.wipe_cache_cached?
                when :wipe_cache_downloads then menu.wipe_cache_downloads?
                when :wipe_cache_annotations then menu.wipe_cache_annotations?
                when :wipe_cache_bookmarks then menu.wipe_cache_bookmarks?
                when :wipe_cache_progress then menu.wipe_cache_progress?
                when :wipe_cache_config then menu.wipe_cache_config?
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
