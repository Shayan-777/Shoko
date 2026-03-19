# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/text_input'
require_relative '../../support/intent_action_group'

module Shoko
  module Application
    module UseCases
      module Reader
        module Actions
          # Routes dictionary intents to the reader dictionary control surface.
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
              @routes ||= dictionary_visibility_routes
                          .merge(dictionary_text_routes)
                          .merge(dictionary_selection_routes)
                          .merge(dictionary_command_routes)
                          .freeze
            end

            def supported_payloads
              nil_payloads(
                :open_dictionary,
                :close_dictionary,
                :dictionary_backspace,
                :dictionary_confirm,
                :dictionary_cycle_result,
                :dictionary_cycle_pair,
                :dictionary_swap_languages,
                :dictionary_toggle_fuzzy
              )
                .merge(text_payloads(:dictionary_insert_text))
                .merge(delta_payloads(:dictionary_move_up, :dictionary_move_down))
                .freeze
            end

            def dictionary_visibility_routes
              handled_routes(:open_dictionary) { @reader_dictionary_control.open_dictionary_lookup }
                .merge(handled_routes(:close_dictionary) { @reader_dictionary_control.close_dictionary_lookup })
            end

            def dictionary_text_routes
              route_map_for(:dictionary_insert_text, payload: :text, result: :handled) do |text|
                @reader_dictionary_control.append_dictionary_text(text)
              end
            end

            def dictionary_selection_routes
              route_map_for(
                %i[dictionary_move_up dictionary_move_down],
                payload: :delta,
                result: :handled
              ) do |delta|
                @reader_dictionary_control.move_dictionary_selection(delta: delta)
              end
            end

            def dictionary_command_routes
              handled_routes(:dictionary_backspace) { @reader_dictionary_control.delete_dictionary_character }
                .merge(handled_routes(:dictionary_confirm) { @reader_dictionary_control.submit_dictionary_lookup })
                .merge(handled_routes(:dictionary_cycle_result) { @reader_dictionary_control.cycle_dictionary_result })
                .merge(handled_routes(:dictionary_cycle_pair) { @reader_dictionary_control.cycle_dictionary_pair })
                .merge(handled_routes(:dictionary_swap_languages) do
                  @reader_dictionary_control.swap_dictionary_languages
                end)
                .merge(handled_routes(:dictionary_toggle_fuzzy) do
                  @reader_dictionary_control.toggle_dictionary_fuzzy_matching
                end)
            end
          end
        end
      end
    end
  end
end
