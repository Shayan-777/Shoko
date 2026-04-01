# frozen_string_literal: true

require_relative '../../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Session-state access helpers for the translator screen.
          module TranslatorScreenComponentStateSupport
            private

            def current_mode
              (menu_state_reader&.mode || :translator).to_sym
            end

            def translator_focus
              (menu_state_reader&.translator_focus || :input).to_sym
            end

            def translator_status
              (menu_state_reader&.translator_status || :idle).to_sym
            end

            def translator_input_text
              menu_state_reader&.translator_input_text.to_s
            end

            def translator_input_cursor
              (menu_state_reader&.translator_input_cursor || translator_input_text.length).to_i
            end

            def translator_output_text
              menu_state_reader&.translator_output_text.to_s
            end

            def translator_message
              menu_state_reader&.translator_message.to_s
            end

            def translator_selection
              normalize_hash(menu_state_reader&.translator_selection)
            end

            def translator_context_menu
              normalize_hash(menu_state_reader&.translator_context_menu)
            end

            def detected_language_label
              detected = menu_state_reader&.translator_detected_source_lang.to_s
              detected.empty? ? '' : "Detected: #{language_name(detected)}"
            end

            def dropdown_selected
              (menu_state_reader&.translator_dropdown_selected || 0).to_i
            end

            def selected_language_code(kind)
              field = kind == :source ? :translator_source_lang : :translator_target_lang
              menu_state_reader&.public_send(field).to_s
            end

            def language_name(code)
              return 'Auto Detect' if code.to_s == 'auto'

              language_options(:target).find { |item| item[:code] == code.to_s }.to_h[:name] || code.to_s
            end

            def language_options(kind)
              languages = Array(menu_state_reader&.translator_languages).map { |item| normalize_language(item) }
              kind == :source ? [{ code: 'auto', name: 'Auto Detect' }, *languages] : languages
            end

            def normalize_language(item)
              normalized = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
              {
                code: normalized[:code].to_s,
                name: normalized[:name].to_s,
              }
            end

            def normalize_hash(value)
              return nil unless value.is_a?(Hash)

              Shoko::Shared::HashNormalizer.symbolize_keys(value)
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end
          end
        end
      end
    end
  end
end
