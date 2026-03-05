# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          module Actions
            module Settings
              # Settings are handled directly via dispatcher bindings
              def toggle_view_mode(_key = nil)
                settings_service.toggle_view_mode
              end

              def toggle_page_numbers(_key = nil)
                settings_service.toggle_page_numbers
              end

              def cycle_line_spacing(_key = nil)
                settings_service.cycle_line_spacing
              end

              def cycle_theme(_key = nil)
                theme = settings_service.cycle_theme
                ui_component_factory&.apply_theme(theme_id: theme)
                theme
              end

              def toggle_highlight_quotes(_key = nil)
                settings_service.toggle_highlight_quotes
              end

              def toggle_dictionary_backend(_key = nil)
                settings_service.toggle_dictionary_backend
              end

              def cycle_dictionary_pair(_key = nil)
                settings_service.cycle_dictionary_pair
              end

              def toggle_kitty_images(_key = nil)
                settings_service.toggle_kitty_images
              end

              def toggle_page_numbering_mode(_key = nil)
                settings_service.toggle_page_numbering_mode
              end

              def wipe_cache(_key = nil)
                message = settings_service.wipe_cache(
                  catalog: @catalog,
                  cached: @menu_state_reader.wipe_cache_cached? || nil,
                  downloads: @menu_state_reader.wipe_cache_downloads? || nil,
                  nuke: @menu_state_reader.wipe_cache_nuke? || nil,
                  annotations: @menu_state_reader.wipe_cache_annotations? || nil,
                  bookmarks: @menu_state_reader.wipe_cache_bookmarks? || nil,
                  progress: @menu_state_reader.wipe_cache_progress? || nil,
                  config_file: @menu_state_reader.wipe_cache_config? || nil
                )
                @filtered_epubs = []
                message
              end

              def toggle_wipe_cache_cached(_key = nil)
                toggle_wipe_cache_flag(:wipe_cache_cached, default: true)
              end

              def toggle_wipe_cache_downloads(_key = nil)
                toggle_wipe_cache_flag(:wipe_cache_downloads, default: false)
              end

              def toggle_wipe_cache_annotations(_key = nil)
                toggle_wipe_cache_flag(:wipe_cache_annotations, default: false)
              end

              def toggle_wipe_cache_bookmarks(_key = nil)
                toggle_wipe_cache_flag(:wipe_cache_bookmarks, default: false)
              end

              def toggle_wipe_cache_progress(_key = nil)
                toggle_wipe_cache_flag(:wipe_cache_progress, default: false)
              end

              def toggle_wipe_cache_config(_key = nil)
                toggle_wipe_cache_flag(:wipe_cache_config, default: false)
              end

              def toggle_wipe_cache_nuke(_key = nil)
                current = @menu_state_reader.wipe_cache_nuke?
                new_value = !current

                payload = { wipe_cache_nuke: new_value }
                if new_value
                  payload[:wipe_cache_cached] = true
                  payload[:wipe_cache_downloads] = true
                  payload[:wipe_cache_annotations] = true
                  payload[:wipe_cache_bookmarks] = true
                  payload[:wipe_cache_progress] = true
                  payload[:wipe_cache_config] = true
                end

                @menu_state_writer.update_menu(payload)
              end

              private

              def toggle_wipe_cache_flag(key, default:)
                current = read_wipe_cache_flag(key, default: default)
                new_val = !current

                payload = { key => new_val }
                payload[:wipe_cache_nuke] = false if !new_val && @menu_state_reader.wipe_cache_nuke?

                @menu_state_writer.update_menu(payload)
              end

              def read_wipe_cache_flag(key, default:)
                case key
                when :wipe_cache_cached then @menu_state_reader.wipe_cache_cached?
                when :wipe_cache_downloads then @menu_state_reader.wipe_cache_downloads?
                when :wipe_cache_annotations then @menu_state_reader.wipe_cache_annotations?
                when :wipe_cache_bookmarks then @menu_state_reader.wipe_cache_bookmarks?
                when :wipe_cache_progress then @menu_state_reader.wipe_cache_progress?
                when :wipe_cache_config then @menu_state_reader.wipe_cache_config?
                else default
                end
              end
            end
          end
        end
      end
    end
  end
end
