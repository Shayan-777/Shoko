# frozen_string_literal: true

require_relative '../../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Download
            module QueryFlow
              private

              def refresh_downloads
                query = @menu_state_reader.download_query.to_s
                @download_workflow.search_downloads(query: query)
                :handled
              end

              def move_download_selection(delta)
                current = (@menu_state_reader.download_selected || 0).to_i
                max_index = [Array(@menu_state_reader.download_results).length - 1, 0].max
                @menu_session_mutator.update_menu(download_selected: (current + delta).clamp(0, max_index))
                :handled
              end

              def activate_download_selection
                book = @menu_runtime.selected_download_book
                @download_workflow.download_book(book) if book
                :handled
              end

              def submit_download_query
                query = @menu_state_reader.download_query.to_s
                @download_workflow.search_downloads(query: query)
                close_download_mode(:download)
              end

              def open_page(page_url)
                return :pass unless page_url

                query = @menu_state_reader.download_query.to_s
                @download_workflow.search_downloads(query: query, page_url: page_url)
                :handled
              end

              def update_query(operation, text = nil)
                current = @menu_state_reader.download_query.to_s
                cursor = (@menu_state_reader.download_cursor || current.length).to_i
                next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                  current,
                  cursor,
                  operation,
                  text: text
                )
                @menu_session_mutator.update_menu(download_query: next_text, download_cursor: next_cursor)
                :handled
              end
            end
          end
        end
      end
    end
  end
end
