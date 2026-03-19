# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Dictionary
            # Shared mode transitions for dictionary menu flows.
            module ModeFlow
              private

              def open_dictionary_mode(mode)
                return open_dictionary_search_mode if mode == :dictionary_search

                reset_dictionary_mode
                @dictionary_workflow.fetch_dictionary_catalog
                :handled
              end

              def close_dictionary_mode(mode)
                target_mode = mode || (current_menu.mode == :dictionary_search ? :dictionary : :settings)
                update_menu(mode: target_mode)
                @menu_mode_control.activate_menu_mode(target_mode)
                :handled
              end

              def submit_dictionary_query
                update_menu(mode: :dictionary, dictionary_selected: 0)
                @menu_mode_control.activate_menu_mode(:dictionary)
                :handled
              end

              def open_dictionary_search_mode
                query = current_menu.dictionary_query.to_s
                update_menu(mode: :dictionary_search, dictionary_cursor: query.length)
                @menu_mode_control.activate_menu_mode(:dictionary_search)
                :handled
              end

              def reset_dictionary_mode
                update_menu(dictionary_mode_payload)
                @menu_mode_control.activate_menu_mode(:dictionary)
              end

              def dictionary_mode_payload
                {
                  mode: :dictionary,
                  dictionary_selected: 0,
                  dictionary_query: '',
                  dictionary_cursor: 0,
                  dictionary_results: [],
                  dictionary_status: :idle,
                  dictionary_message: '',
                  dictionary_progress: 0.0,
                }
              end
            end
          end
        end
      end
    end
  end
end
