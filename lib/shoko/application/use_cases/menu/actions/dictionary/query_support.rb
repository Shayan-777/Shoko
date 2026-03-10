# frozen_string_literal: true

require_relative '../../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Dictionary
            module QuerySupport
              private

              def update_query(operation, text = nil)
                current = @menu_state_reader.dictionary_query.to_s
                cursor = (@menu_state_reader.dictionary_cursor || current.length).to_i
                next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                  current,
                  cursor,
                  operation,
                  text: text
                )
                @menu_session_mutator.update_menu(dictionary_query: next_text, dictionary_cursor: next_cursor)
                :handled
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

              def dictionary_action_count
                Shoko::Shared::MenuDefinitions.dictionary_action_items.length
              end
            end
          end
        end
      end
    end
  end
end
