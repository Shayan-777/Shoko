# frozen_string_literal: true

require_relative '../../../../../shared/menu_definitions'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Dictionary
            # Selection movement and activation helpers for dictionary mode.
            module SelectionFlow
              private

              def move_dictionary_selection(delta)
                current = (current_menu.dictionary_selected || 0).to_i
                max_index = [dictionary_action_count + dictionary_filtered_results.length - 1, 0].max
                update_menu(dictionary_selected: (current + delta).clamp(0, max_index))
                :handled
              end

              def activate_dictionary_selection
                index = (current_menu.dictionary_selected || 0).to_i

                if index < dictionary_action_count
                  handle_dictionary_action(index)
                else
                  entry = dictionary_filtered_results[index - dictionary_action_count]
                  @dictionary_workflow.download_dictionary(entry) if entry
                end

                :handled
              end

              def handle_dictionary_action(index)
                action = Shoko::Shared::MenuDefinitions.dictionary_action_item(index)&.action

                case action
                when :dictionary_back
                  close_dictionary_mode(:settings)
                when :toggle_dictionary_backend
                  @settings_service.toggle_dictionary_backend
                when :cycle_dictionary_pair
                  @settings_service.cycle_dictionary_pair
                when :dictionary_refresh
                  @dictionary_workflow.fetch_dictionary_catalog
                end
              end
            end
          end
        end
      end
    end
  end
end
