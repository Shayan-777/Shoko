# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
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
              edit_reader_dictionary_query
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
                :close_dictionary,
                :dictionary_confirm,
                :dictionary_cycle_result,
                :dictionary_cycle_pair,
                :dictionary_swap_languages,
                :dictionary_toggle_fuzzy
              )
                .merge(open_dictionary: [Hash, NilClass])
                .merge(edit_op_payloads(:edit_reader_dictionary_query))
                .merge(delta_payloads(:dictionary_move_up, :dictionary_move_down))
                .freeze
            end

            def dictionary_visibility_routes
              {
                open_dictionary: route(payload: :raw, result: :handled) do |context|
                  @reader_dictionary_control.open_dictionary_lookup(context)
                end,
              }
                .merge(handled_routes(:close_dictionary) { @reader_dictionary_control.close_dictionary_lookup })
            end

            def dictionary_text_routes
              {
                edit_reader_dictionary_query: route(payload: :edit_op, result: :handled) do |op|
                  apply_dictionary_edit(op)
                end,
              }
            end

            def apply_dictionary_edit(op)
              case op.operation
              when :insert    then @reader_dictionary_control.append_dictionary_text(op.text)
              when :backspace then @reader_dictionary_control.delete_dictionary_character
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
              handled_routes(:dictionary_confirm) { @reader_dictionary_control.submit_dictionary_lookup }
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
