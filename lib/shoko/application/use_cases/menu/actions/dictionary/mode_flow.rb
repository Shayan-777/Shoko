# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Dictionary
            module ModeFlow
              private

              def open_dictionary_mode(mode)
                if mode == :dictionary_search
                  query = @menu_state_reader.dictionary_query.to_s
                  @menu_session_mutator.update_menu(mode: :dictionary_search, dictionary_cursor: query.length)
                  @menu_runtime.activate_mode(:dictionary_search)
                  return :handled
                end

                @menu_session_mutator.update_menu(
                  mode: :dictionary,
                  dictionary_selected: 0,
                  dictionary_query: '',
                  dictionary_cursor: 0,
                  dictionary_results: [],
                  dictionary_status: :idle,
                  dictionary_message: '',
                  dictionary_progress: 0.0
                )
                @menu_runtime.activate_mode(:dictionary)
                @dictionary_workflow.fetch_dictionary_catalog
                :handled
              end

              def close_dictionary_mode(mode)
                target_mode = mode || (@menu_state_reader.mode == :dictionary_search ? :dictionary : :settings)
                @menu_session_mutator.update_menu(mode: target_mode)
                @menu_runtime.activate_mode(target_mode)
                :handled
              end

              def submit_dictionary_query
                @menu_session_mutator.update_menu(mode: :dictionary, dictionary_selected: 0)
                @menu_runtime.activate_mode(:dictionary)
                :handled
              end
            end
          end
        end
      end
    end
  end
end
