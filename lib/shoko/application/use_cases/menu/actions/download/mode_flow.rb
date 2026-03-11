# frozen_string_literal: true

require_relative '../../../../../shared/download_source_policy'

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

                current_source = Shoko::Shared::DownloadSourcePolicy.normalize(download_config.download_source) ||
                                 Shoko::Shared::DownloadSourcePolicy.default_id
                source_index = Shoko::Shared::DownloadSourcePolicy.canonical_ids.index(current_source) || 0
                update_menu(
                  mode: :download,
                  download_query: '',
                  download_cursor: 0,
                  download_source_selected: source_index,
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

              def download_config
                @app_config_store.load
              end
            end
          end
        end
      end
    end
  end
end
