# frozen_string_literal: true

require 'shoko/application/ports/inbound/menu_catalog'
require_relative '../../requests/selection_delta'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles settings selection and activation intents from the menu.
          class Settings
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

            SETTINGS_ACTIONS = Shoko::Application::Ports::Inbound::MenuCatalog.settings_actions
            MOVE_INTENTS = %i[move_settings_selection_up move_settings_selection_down].freeze

            SUPPORTED_INTENTS = %i[
              move_settings_selection_up
              move_settings_selection_down
              activate_settings_selection
            ].freeze

            def initialize(menu_session_store:, settings_service:, catalog:, navigation_actions:, dictionary_actions:,
                           translator_packs_actions:, menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @settings_service = settings_service
              @catalog = catalog
              @navigation_actions = navigation_actions
              @dictionary_actions = dictionary_actions
              @translator_packs_actions = translator_packs_actions
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu settings intent')
            end

            SETTINGS_SERVICE_ACTIONS = {
              toggle_view_mode: lambda(&:toggle_view_mode),
              cycle_line_spacing: lambda(&:cycle_line_spacing),
              cycle_paragraph_style: lambda(&:cycle_paragraph_style),
              cycle_justify: lambda(&:cycle_justify),
              toggle_book_colors: lambda(&:toggle_book_colors),
              cycle_download_source: lambda(&:cycle_download_source),
              cycle_theme: lambda(&:cycle_theme),
              toggle_page_numbering_mode: lambda(&:toggle_page_numbering_mode),
              toggle_page_numbers: lambda(&:toggle_page_numbers),
              toggle_highlight_quotes: lambda(&:toggle_highlight_quotes),
              toggle_kitty_images: lambda(&:toggle_kitty_images),
              toggle_prepaginate_on_resize: lambda(&:toggle_prepaginate_on_resize),
            }.freeze
            WIPE_CACHE_FLAG_ACTIONS = {
              toggle_wipe_cache_cached: { key: :wipe_cache_cached, default: true },
              toggle_wipe_cache_downloads: { key: :wipe_cache_downloads, default: false },
              toggle_wipe_cache_dictionary: { key: :wipe_cache_dictionary, default: false },
              toggle_wipe_cache_annotations: { key: :wipe_cache_annotations, default: false },
              toggle_wipe_cache_bookmarks: { key: :wipe_cache_bookmarks, default: false },
              toggle_wipe_cache_progress: { key: :wipe_cache_progress, default: false },
              toggle_wipe_cache_config: { key: :wipe_cache_config, default: false },
            }.freeze

            private

            def routes
              @routes ||= handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| shift_settings_selection(delta) }
                          .merge(activate_settings_selection: route { activate_settings_selection })
                          .freeze
            end

            def supported_payloads
              delta_payloads(*MOVE_INTENTS).merge(nil_payloads(:activate_settings_selection))
            end

            def shift_settings_selection(delta)
              current = (current_menu.settings_selected || 0).to_i
              max_index = SETTINGS_ACTIONS.length - 1
              update_menu(settings_selected: (current + delta).clamp(0, max_index))
              :handled
            end

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
              when :open_translator_packs
                @translator_packs_actions.call(:open_translator_packs_mode)
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
                dictionary: menu.wipe_cache_dictionary? || nil,
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
              when :wipe_cache_dictionary then menu.wipe_cache_dictionary?
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
