# frozen_string_literal: true

require_relative '../../../../../shared/menu_definitions'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
            module Actions
              module Dictionary
              def open_dictionary_settings(_key = nil)
                reset_dictionary_state
                @menu_state_writer.update_menu(mode: :dictionary, dictionary_selected: 0)
                input_controller.activate(:dictionary)
                state_controller.fetch_dictionary_catalog
              end

              def dictionary_up(_key = nil)
                update_dictionary_selection(-1)
              end

              def dictionary_down(_key = nil)
                update_dictionary_selection(1)
              end

              def dictionary_select(_key = nil)
                index = (@menu_state_reader.dictionary_selected || 0).to_i
                action_count = dictionary_action_count

                if index < action_count
                  handle_dictionary_action(index)
                else
                  entry = selected_dictionary_entry
                  state_controller.download_dictionary(entry) if entry
                end
              end

              def dictionary_start_search(_key = nil)
                query = @menu_state_reader.dictionary_query.to_s
                @menu_state_writer.update_menu(mode: :dictionary_search, dictionary_cursor: query.length)
                input_controller.activate(:dictionary_search)
              end

              def dictionary_back(_key = nil)
                @menu_state_writer.update_menu(mode: :settings)
                input_controller.activate(:settings)
              end

              def dictionary_exit_search(_key = nil)
                @menu_state_writer.update_menu(mode: :dictionary)
                input_controller.activate(:dictionary)
              end

              def dictionary_submit_search(_key = nil)
                @menu_state_writer.update_menu(mode: :dictionary, dictionary_selected: 0)
                input_controller.activate(:dictionary)
              end

              def dictionary_refresh(_key = nil)
                state_controller.fetch_dictionary_catalog
              end

            private

              def update_dictionary_selection(delta)
                max_index = [dictionary_item_count - 1, 0].max
                current = (@menu_state_reader.dictionary_selected || 0).to_i
                new_val = (current + delta).clamp(0, max_index)
                @menu_state_writer.update_menu(dictionary_selected: new_val)
              end

              def dictionary_item_count
                dictionary_action_count + dictionary_filtered_results.length
              end

              def dictionary_action_count
                Shoko::Shared::MenuDefinitions.dictionary_action_items.length
              end

              def dictionary_filtered_results
                query = @menu_state_reader.dictionary_query.to_s.downcase
                results = Array(@menu_state_reader.dictionary_results)
                return results if query.empty?

                results.select do |item|
                  name = item[:name].to_s.downcase
                  pair = "#{item[:source]}-#{item[:target]}".downcase
                  name.include?(query) || pair.include?(query)
                end
              end

              def selected_dictionary_entry
                index = (@menu_state_reader.dictionary_selected || 0).to_i
                list_index = index - dictionary_action_count
                return nil if list_index.negative?

                dictionary_filtered_results[list_index]
              end

              def handle_dictionary_action(index)
                item = Shoko::Shared::MenuDefinitions.dictionary_action_item(index)
                action = item&.action
                return if action.nil?

                case action
                when :dictionary_back then dictionary_back
                when :toggle_dictionary_backend then toggle_dictionary_backend
                when :cycle_dictionary_pair then cycle_dictionary_pair
                when :dictionary_refresh then dictionary_refresh
                else
                  raise ArgumentError, "Unsupported dictionary action: #{action}"
                end
              end
            end
          end
        end
      end
    end
  end
end
