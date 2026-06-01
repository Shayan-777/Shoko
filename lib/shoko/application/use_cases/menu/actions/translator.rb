# frozen_string_literal: true

require_relative '../../requests/selection_delta'
require_relative '../../requests/edit_op'
require_relative '../../support/intent_action_group'
require_relative '../../support/menu_session_access'
require_relative '../../../../shared/hash_normalizer'
require_relative '../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          # Handles translator mode editing, dropdown selection, and submission.
          class Translator
            include Shoko::Application::UseCases::Support::IntentActionGroup
            include Shoko::Application::UseCases::Support::MenuSessionAccess

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


            def move_dropdown_selection(delta)
              return unless dropdown_mode?

              current = (current_menu.translator_dropdown_selected || 0).to_i
              max_index = [dropdown_options.length - 1, 0].max
              update_menu(translator_dropdown_selected: (current + delta).clamp(0, max_index))
            end

            def confirm_language_selection
              return unless dropdown_mode?

              apply_language_selection(code: selected_dropdown_code, kind: current_dropdown_kind)
            end

            def open_dropdown(kind)
              mode = kind == :source ? :translator_source_dropdown : :translator_target_dropdown
              update_menu(
                mode: mode,
                translator_focus: kind,
                translator_dropdown_selected: language_index(kind, current_language_code(kind)),
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def apply_language_selection(code:, kind:)
              field = kind == :source ? :translator_source_lang : :translator_target_lang
              update_menu(
                {
                  mode: :translator,
                  translator_focus: kind,
                  translator_selection: nil,
                  translator_context_menu: nil,
                  field => code,
                }
              )
              submit_translation_if_needed
            end

            def dropdown_mode?
              %i[translator_source_dropdown translator_target_dropdown].include?(current_menu.mode)
            end

            def current_dropdown_kind
              current_menu.mode == :translator_target_dropdown ? :target : :source
            end

            def translator_focus
              (current_menu.translator_focus || :input).to_sym
            end

            def next_focus_for(current)
              order = %i[source input target]
              index = order.index((current || :input).to_sym) || 1
              order[(index + 1) % order.length]
            end

            def current_language_code(kind)
              kind == :source ? current_menu.translator_source_lang : current_menu.translator_target_lang
            end

            def selected_dropdown_code
              dropdown_options.fetch((current_menu.translator_dropdown_selected || 0).to_i, {})
                              .fetch(:code, current_language_code(current_dropdown_kind).to_s)
            end

            def language_index(kind, code)
              options = dropdown_options(kind)
              options.index { |item| item[:code] == code.to_s } || 0
            end

            def dropdown_options(kind = current_dropdown_kind)
              languages = Array(current_menu.translator_languages).map { |item| normalize_language(item) }
              return [{ code: 'auto', name: 'Auto Detect' }, *languages] if kind == :source

              languages
            end

            def normalize_language(item)
              normalized = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
              code = normalized[:code]
              name = normalized[:name]
              { code: code.to_s, name: name.to_s }
            end


            def update_input(operation, text = nil)
              return unless translator_focus == :input && current_menu.mode == :translator

              current = current_menu.translator_input_text.to_s
              cursor = (current_menu.translator_input_cursor || current.length).to_i
              next_text, next_cursor = Shoko::Application::UseCases::Support::TextEditing.apply_edit(
                current,
                cursor,
                operation,
                text: text
              )
              update_menu(
                translator_input_text: next_text,
                translator_input_cursor: next_cursor,
                translator_selection: nil,
                translator_context_menu: nil
              )
            end

            def submit_translation
              @translator_workflow.fetch_translation_languages if Array(current_menu.translator_languages).empty?
              @translator_workflow.translate_text(
                text: current_menu.translator_input_text,
                source_lang: current_menu.translator_source_lang,
                target_lang: current_menu.translator_target_lang
              )
            end

            def submit_translation_if_needed
              return if current_menu.translator_input_text.to_s.strip.empty?

              submit_translation
            end

          end
        end
      end
    end
  end
end
