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
              case intent
              when :open_dictionary
                validate_payload!(intent, payload)
                @reader_dictionary_control.open_dictionary_lookup
              when :close_dictionary
                validate_payload!(intent, payload)
                @reader_dictionary_control.close_dictionary_lookup
              when :dictionary_insert_text
                @reader_dictionary_control.append_dictionary_text(text_from(payload, intent))
              when :dictionary_backspace
                validate_payload!(intent, payload)
                @reader_dictionary_control.delete_dictionary_character
              when :dictionary_confirm
                validate_payload!(intent, payload)
                @reader_dictionary_control.submit_dictionary_lookup
              when :dictionary_move_up
                @reader_dictionary_control.move_dictionary_selection(delta: positive_delta(payload, intent))
              when :dictionary_move_down
                @reader_dictionary_control.move_dictionary_selection(delta: positive_delta(payload, intent))
              when :dictionary_cycle_result
                validate_payload!(intent, payload)
                @reader_dictionary_control.cycle_dictionary_result
              when :dictionary_cycle_pair
                validate_payload!(intent, payload)
                @reader_dictionary_control.cycle_dictionary_pair
              when :dictionary_swap_languages
                validate_payload!(intent, payload)
                @reader_dictionary_control.swap_dictionary_languages
              when :dictionary_toggle_fuzzy
                validate_payload!(intent, payload)
                @reader_dictionary_control.toggle_dictionary_fuzzy_matching
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
