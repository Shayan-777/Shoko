# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          class Dictionary
            include Shoko::Application::UseCases::Support::IntentActionGroup

            SUPPORTED_INTENTS = %i[
              open_dictionary
              close_dictionary
              dictionary_insert_text
              dictionary_backspace
              dictionary_confirm
              dictionary_move_up
              dictionary_move_down
              dictionary_cycle_result
              dictionary_cycle_pair
              dictionary_swap_languages
              dictionary_toggle_fuzzy
            ].freeze

            def initialize(reader_dictionary_control:)
              @reader_dictionary_control = reader_dictionary_control
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported reader dictionary intent')
            end

            private

            def routes
              @routes ||= {
                open_dictionary: route(result: :handled) { @reader_dictionary_control.open_dictionary_lookup },
                close_dictionary: route(result: :handled) { @reader_dictionary_control.close_dictionary_lookup },
                dictionary_insert_text: route(payload: :text, result: :handled) do |text|
                  @reader_dictionary_control.append_dictionary_text(text)
                end,
                dictionary_backspace: route(result: :handled) { @reader_dictionary_control.delete_dictionary_character },
                dictionary_confirm: route(result: :handled) { @reader_dictionary_control.submit_dictionary_lookup },
                dictionary_move_up: route(payload: :delta, result: :handled) do |delta|
                  @reader_dictionary_control.move_dictionary_selection(delta: delta)
                end,
                dictionary_move_down: route(payload: :delta, result: :handled) do |delta|
                  @reader_dictionary_control.move_dictionary_selection(delta: delta)
                end,
                dictionary_cycle_result: route(result: :handled) { @reader_dictionary_control.cycle_dictionary_result },
                dictionary_cycle_pair: route(result: :handled) { @reader_dictionary_control.cycle_dictionary_pair },
                dictionary_swap_languages: route(result: :handled) { @reader_dictionary_control.swap_dictionary_languages },
                dictionary_toggle_fuzzy: route(result: :handled) do
                  @reader_dictionary_control.toggle_dictionary_fuzzy_matching
                end,
              }.freeze
            end

            def supported_payloads
              {
                open_dictionary: [NilClass],
                close_dictionary: [NilClass],
                dictionary_insert_text: [Shoko::Application::UseCases::Requests::TextInput],
                dictionary_backspace: [NilClass],
                dictionary_confirm: [NilClass],
                dictionary_move_up: [Shoko::Application::UseCases::Requests::SelectionDelta],
                dictionary_move_down: [Shoko::Application::UseCases::Requests::SelectionDelta],
                dictionary_cycle_result: [NilClass],
                dictionary_cycle_pair: [NilClass],
                dictionary_swap_languages: [NilClass],
                dictionary_toggle_fuzzy: [NilClass],
              }
            end
          end
        end
      end
    end
  end
end
