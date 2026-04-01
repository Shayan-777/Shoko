# frozen_string_literal: true

require_relative '../../../support/text_editing'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Translator
            # Input editing and submission helpers for translator mode.
            module InputSupport
              private

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
end
