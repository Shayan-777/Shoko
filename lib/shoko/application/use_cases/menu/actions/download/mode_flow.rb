# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Download
            module ModeFlow
              private

              def open_download_mode(mode)
                if mode == :download_search
                  query = current_menu.download_query.to_s
                  update_menu(mode: :download_search, download_cursor: query.length)
                  @menu_mode_control.activate_menu_mode(:download_search)
                  return :handled
                end

                update_menu(
                  mode: :download,
                  download_query: '',
                  download_cursor: 0,
                  download_selected: 0,
                  download_results: [],
                  download_count: 0,
                  download_next: nil,
                  download_prev: nil,
                  download_status: :idle,
                  download_message: '',
                  download_progress: 0.0
                )
                @menu_mode_control.activate_menu_mode(:download)
                :handled
              end

              def close_download_mode(mode)
                target_mode = mode || (current_menu.mode == :download_search ? :download : :menu)
                update_menu(mode: target_mode)
                @menu_mode_control.activate_menu_mode(target_mode)
                :handled
              end
            end
          end
        end
      end
    end
  end
end
