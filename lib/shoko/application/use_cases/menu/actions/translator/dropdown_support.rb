# frozen_string_literal: true

require_relative '../../../../../shared/hash_normalizer'

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class Translator
            # Dropdown state helpers and language normalization for translator mode.
            module DropdownSupport
              private

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
            end
          end
        end
      end
    end
  end
end
