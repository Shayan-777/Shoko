# frozen_string_literal: true

require_relative '../../../../../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          module Actions
            module Lifecycle
              # Translator-specific mouse event routing extracted from the main loop.
              module TranslatorMouseFlow
                private

                def sync_menu_mouse_tracking
                  return enable_menu_mouse_tracking if translator_mouse_mode? && !@menu_mouse_tracking
                  return disable_menu_mouse_tracking if !translator_mouse_mode? && @menu_mouse_tracking

                  nil
                end

                def enable_menu_mouse_tracking
                  @terminal_service.enable_mouse
                  @menu_mouse_tracking = true
                end

                def disable_menu_mouse_tracking
                  return unless @menu_mouse_tracking

                  @terminal_service.disable_mouse
                  @menu_mouse_tracking = false
                rescue Shoko::Error
                  @menu_mouse_tracking = false
                end

                def consume_menu_mouse_input(keys)
                  return Array(keys) unless translator_mouse_mode?

                  Array(keys).each_with_object([]) do |key, remaining|
                    translator_mouse_sequence?(key) ? handle_translator_mouse_sequence(key) : remaining << key
                  end
                end

                def translator_mouse_sequence?(token)
                  @mouse_handler&.mouse_sequence?(token)
                end

                def handle_translator_mouse_sequence(token)
                  event = @mouse_handler.parse_mouse_event(token)
                  return unless event
                  return if @translator_mouse_handler&.handle(event, bounds: translator_bounds)
                  return unless translator_click_release?(event)

                  action = translator_screen.hit_test(event[:x] + 1, event[:y] + 1, translator_bounds)
                  apply_translator_mouse_action(action)
                end

                def translator_click_release?(event)
                  event[:released] && event[:button].to_i.zero?
                end

                def translator_bounds
                  height, width = @terminal_service.size
                  Struct.new(:width, :height).new(width, height)
                end

                def apply_translator_mouse_action(action)
                  return unless action

                  case action[:type]
                  when :focus then focus_translator_input
                  when :toggle_dropdown then toggle_translator_dropdown(action[:kind])
                  when :select_language then select_translator_language(action)
                  end
                end

                def focus_translator_input
                  @menu_session_mutator.update_menu(
                    mode: :translator,
                    translator_focus: :input,
                    translator_selection: nil,
                    translator_context_menu: nil
                  )
                end

                def toggle_translator_dropdown(kind)
                  dropdown_mode = kind == :source ? :translator_source_dropdown : :translator_target_dropdown
                  return close_translator_dropdown(kind) if @menu_state_reader.mode == dropdown_mode

                  open_translator_dropdown(kind, dropdown_mode)
                end

                def close_translator_dropdown(kind)
                  @menu_session_mutator.update_menu(
                    mode: :translator,
                    translator_focus: kind,
                    translator_selection: nil,
                    translator_context_menu: nil
                  )
                end

                def open_translator_dropdown(kind, dropdown_mode)
                  @menu_session_mutator.update_menu(
                    mode: dropdown_mode,
                    translator_focus: kind,
                    translator_dropdown_selected: translator_language_index(kind),
                    translator_selection: nil,
                    translator_context_menu: nil
                  )
                end

                def select_translator_language(action)
                  @menu_session_mutator.update_menu(translator_language_payload(action))
                  translate_from_current_translator_state
                end

                def translator_language_payload(action)
                  field = action[:kind] == :source ? :translator_source_lang : :translator_target_lang
                  {
                    mode: :translator,
                    translator_focus: action[:kind],
                    translator_dropdown_selected: action[:index],
                    translator_selection: nil,
                    translator_context_menu: nil,
                    field => action[:code],
                  }
                end

                def translate_from_current_translator_state
                  text = @menu_state_reader.translator_input_text.to_s
                  return if text.strip.empty?

                  @state_controller.translate_text(
                    text: text,
                    source_lang: @menu_state_reader.translator_source_lang,
                    target_lang: @menu_state_reader.translator_target_lang
                  )
                end

                def translator_language_index(kind)
                  code = selected_translator_language_code(kind)
                  translator_language_options(kind).index { |item| item[:code] == code.to_s } || 0
                end

                def selected_translator_language_code(kind)
                  return @menu_state_reader.translator_source_lang if kind == :source

                  @menu_state_reader.translator_target_lang
                end

                def translator_language_options(kind)
                  languages = Array(@menu_state_reader.translator_languages).map { |item| normalize_language(item) }
                  kind == :source ? [{ code: 'auto', name: 'Auto Detect' }, *languages] : languages
                end

                def normalize_language(item)
                  normalized = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
                  {
                    code: normalized[:code].to_s,
                    name: normalized[:name].to_s,
                  }
                end

                def translator_mouse_mode?
                  %i[translator translator_source_dropdown translator_target_dropdown].include?(@menu_state_reader.mode)
                end

                def translator_screen
                  @main_menu_component.translator_screen
                end
              end
            end
          end
        end
      end
    end
  end
end
