# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative 'translator/dropdown_support'
require_relative 'translator/input_support'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles translator mode editing, dropdown selection, and submission.
          class Translator
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess
            include DropdownSupport
            include InputSupport

            MOVE_INTENTS = %i[
              move_translator_language_selection_up
              move_translator_language_selection_down
            ].freeze
            SUPPORTED_INTENTS = %i[
              close_translator_mode
              close_translator_dropdown
              translator_cycle_focus
              translator_activate_focus
              translator_swap_languages
              edit_translator_input
              move_translator_language_selection_up
              move_translator_language_selection_down
              activate_translator_language_selection
            ].freeze

            def initialize(menu_session_store:, translator_workflow:, menu_transient_store:)
              assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
              @translator_workflow = translator_workflow
            end

            def call(intent, payload = nil)
              dispatch_route(intent, payload, routes, unsupported: 'unsupported menu translator intent')
            end

            private

            def routes
              @routes ||= mode_routes.merge(input_routes).merge(dropdown_routes).freeze
            end

            def supported_payloads
              nil_payloads(
                :close_translator_mode,
                :close_translator_dropdown,
                :translator_cycle_focus,
                :translator_activate_focus,
                :translator_swap_languages,
                :activate_translator_language_selection
              )
                .merge(edit_op_payloads(:edit_translator_input))
                .merge(delta_payloads(*MOVE_INTENTS))
            end

            def mode_routes
              {
                close_translator_mode: route(result: :handled) { close_translator_mode },
                close_translator_dropdown: route(result: :handled) { close_translator_dropdown },
                translator_cycle_focus: route(result: :handled) { cycle_focus },
                translator_activate_focus: route(result: :handled) { activate_focus },
                translator_swap_languages: route(result: :handled) { swap_languages },
              }
            end

            def input_routes
              {
                edit_translator_input: route(payload: :edit_op, result: :handled) do |op|
                  update_input(op.operation, op.text)
                end,
              }
            end

            def dropdown_routes
              handled_routes(*MOVE_INTENTS, payload: :delta) { |delta| move_dropdown_selection(delta) }
                .merge(activate_translator_language_selection: route(result: :handled) { confirm_language_selection })
            end

            def close_translator_mode
              update_menu(
                mode: :menu,
                translator_focus: :input,
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def close_translator_dropdown
              update_menu(
                mode: :translator,
                translator_focus: current_dropdown_kind,
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def cycle_focus
              return if dropdown_mode?

              update_menu(
                translator_focus: next_focus_for(current_menu.translator_focus),
                translator_context_menu: nil
              )
            end

            def activate_focus
              return confirm_language_selection if dropdown_mode?

              translator_focus == :input ? submit_translation : open_dropdown(translator_focus)
            end

            def swap_languages
              return if current_menu.translator_source_lang.to_s == 'auto'

              update_menu(
                translator_source_lang: current_menu.translator_target_lang,
                translator_target_lang: current_menu.translator_source_lang,
                translator_selection: nil,
                translator_context_menu: nil
              )
              submit_translation_if_needed
            end
          end
        end
      end
    end
  end
end
