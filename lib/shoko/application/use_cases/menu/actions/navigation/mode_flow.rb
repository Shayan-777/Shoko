# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Navigation
            # Shared mode-switch helpers for main menu navigation.
            module ModeFlow
              private

              def switch_browse_mode
                update_menu(mode: :browse, search_active: false)
                @menu_mode_control.activate_menu_mode(:browse)
                :handled
              end

              def switch_search_mode
                update_menu(mode: :search, search_active: true)
                @menu_mode_control.activate_menu_mode(:search)
                :handled
              end

              def open_annotations_mode
                preload_annotations
                switch_mode(:annotations)
              end

              def switch_mode(mode)
                payload = { mode: mode, browse_selected: 0 }
                payload[:settings_selected] = 1 if mode == :settings
                payload[:library_details_open] = false if mode == :library
                update_menu(payload)
                @menu_mode_control.activate_menu_mode(mode)
                :handled
              end

              def preload_annotations
                annotations = @annotation_service ? @annotation_service.list_all : {}
                update_menu(annotations_all: annotations || {})
              rescue Shoko::Error => e
                @logger&.error('menu.preload_annotations.failed', error: e.class.name, message: e.message)
                update_menu(annotations_all: {})
              end

              def open_download_mode
                update_menu(download_mode_payload)
                @menu_mode_control.activate_menu_mode(:download)
                :handled
              end

              def quit_application
                @application_exit_control.quit_application(code: 0, message: '')
                :handled
              end

              def download_mode_payload
                {
                  mode: :download,
                  browse_selected: 0,
                  download_query: '',
                  download_cursor: 0,
                  download_selected: 0,
                  download_results: [],
                  download_count: 0,
                  download_next: nil,
                  download_prev: nil,
                  download_status: :idle,
                  download_message: '',
                  download_progress: 0.0,
                }
              end
            end
          end
        end
      end
    end
  end
end
