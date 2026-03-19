# frozen_string_literal: true

require_relative '../../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Dictionary
            # Query-editing and filtering helpers for dictionary mode.
            module QuerySupport
              private

              def update_query(operation, text = nil)
                menu = current_menu
                current = menu.dictionary_query.to_s
                cursor = (menu.dictionary_cursor || current.length).to_i
                next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                  current,
                  cursor,
                  operation,
                  text: text
                )
                update_menu(dictionary_query: next_text, dictionary_cursor: next_cursor)
                :handled
              end

              def dictionary_filtered_results
                menu = current_menu
                query = menu.dictionary_query.to_s.downcase
                results = Array(menu.dictionary_results)
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
