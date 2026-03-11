# frozen_string_literal: true

require_relative '../../../../../shared/download_source_policy'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Download
            module SourceFlow
              private

              def open_download_source_mode
                update_menu(
                  mode: :download_source_select,
                  download_source_selected: current_download_source_index
                )
                @menu_mode_control.activate_menu_mode(:download_source_select)
                :handled
              end

              def close_download_source_mode(mode)
                target_mode = mode || :download
                update_menu(mode: target_mode)
                @menu_mode_control.activate_menu_mode(target_mode)
                :handled
              end

              def move_download_source_selection(delta)
                current = (current_menu.download_source_selected || current_download_source_index).to_i
                max_index = source_options.length - 1
                update_menu(download_source_selected: (current + delta).clamp(0, max_index))
                :handled
              end

              def activate_download_source_selection
                selected_source = source_options.fetch(selected_download_source_index, current_download_source)
                @settings_service.set_download_source(selected_source)
                update_menu(mode: :download, download_source_selected: selected_download_source_index)
                @menu_mode_control.activate_menu_mode(:download)

                query = current_menu.download_query.to_s.strip
                if query.empty?
                  update_menu(
                    download_results: [],
                    download_count: 0,
                    download_next: nil,
                    download_prev: nil,
                    download_selected: 0,
                    download_status: :done,
                    download_message: "Download source set to #{download_source_label(selected_source)}",
                    download_progress: 0.0
                  )
                else
                  @download_workflow.search_downloads(query: query)
                end
                :handled
              end

              def selected_download_source_index
                max_index = source_options.length - 1
                (current_menu.download_source_selected || current_download_source_index).to_i.clamp(0, max_index)
              end

              def current_download_source_index
                source_options.index(current_download_source) || 0
              end

              def current_download_source
                Shoko::Shared::DownloadSourcePolicy.normalize(config_snapshot.download_source) ||
                  Shoko::Shared::DownloadSourcePolicy.default_id
              end

              def config_snapshot
                @app_config_store.load
              end

              def source_options
                Shoko::Shared::DownloadSourcePolicy.canonical_ids
              end

              def download_source_label(source)
                Shoko::Shared::DownloadSourcePolicy.label_for(source)
              end
            end
          end
        end
      end
    end
  end
end
