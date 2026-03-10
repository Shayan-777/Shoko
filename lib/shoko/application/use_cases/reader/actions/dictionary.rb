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

            def initialize(reader_runtime:)
              @reader_runtime = reader_runtime
            end

            def call(intent, payload = nil)
              case intent
              when :open_dictionary
                validate_payload!(intent, payload)
                @reader_runtime.open_dictionary
              when :close_dictionary
                validate_payload!(intent, payload)
                @reader_runtime.close_dictionary
              when :dictionary_insert_text
                @reader_runtime.dictionary_insert_text(text_from(payload, intent))
              when :dictionary_backspace
                validate_payload!(intent, payload)
                @reader_runtime.dictionary_backspace
              when :dictionary_confirm
                validate_payload!(intent, payload)
                @reader_runtime.dictionary_confirm
              when :dictionary_move_up
                @reader_runtime.dictionary_move(positive_delta(payload, intent))
              when :dictionary_move_down
                @reader_runtime.dictionary_move(positive_delta(payload, intent))
              when :dictionary_cycle_result
                validate_payload!(intent, payload)
                @reader_runtime.dictionary_cycle_result
              when :dictionary_cycle_pair
                validate_payload!(intent, payload)
                @reader_runtime.dictionary_cycle_pair
              when :dictionary_swap_languages
                validate_payload!(intent, payload)
                @reader_runtime.dictionary_swap_languages
              when :dictionary_toggle_fuzzy
                validate_payload!(intent, payload)
                @reader_runtime.dictionary_toggle_fuzzy
              else
                raise ArgumentError, "unsupported reader dictionary intent: #{intent}"
              end

              :handled
            end

            private

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
