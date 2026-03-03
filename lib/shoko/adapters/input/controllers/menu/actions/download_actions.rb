# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
            module Actions
              module Download
              def open_download_screen(_key = nil)
                reset_download_state
                @menu_state_writer.update_menu(mode: :download)
                input_controller.activate(@menu_state_reader.mode)
              end

              def download_start_search(_key = nil)
                query = @menu_state_reader.download_query.to_s
                @menu_state_writer.update_menu(mode: :download_search, download_cursor: query.length)
                input_controller.activate(@menu_state_reader.mode)
              end

              def download_exit_search(_key = nil)
                @menu_state_writer.update_menu(mode: :download)
                input_controller.activate(@menu_state_reader.mode)
              end

              def download_submit_search(_key = nil)
                query = @menu_state_reader.download_query.to_s
                state_controller.search_downloads(query: query)
                download_exit_search
              end

              def download_refresh(_key = nil)
                query = @menu_state_reader.download_query.to_s
                state_controller.search_downloads(query: query)
              end

              def download_next_page(_key = nil)
                next_url = @menu_state_reader.download_next
                return unless next_url

                query = @menu_state_reader.download_query.to_s
                state_controller.search_downloads(query: query, page_url: next_url)
              end

              def download_prev_page(_key = nil)
                prev_url = @menu_state_reader.download_prev
                return unless prev_url

                query = @menu_state_reader.download_query.to_s
                state_controller.search_downloads(query: query, page_url: prev_url)
              end

              def download_up(_key = nil)
                update_download_selection(-1)
              end

              def download_down(_key = nil)
                update_download_selection(1)
              end

              def download_confirm(_key = nil)
                book = selected_download_book
                return unless book

                state_controller.download_book(book)
              end
            end
          end
        end
      end
    end
  end
end
