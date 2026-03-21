# frozen_string_literal: true

require_relative '../support/message_notifier'
require_relative '../../../../shared/key_definitions'

module Shoko
  module Adapters
    module Input
      module Controllers
        # UI-controller owned translation popup flow for selection context actions.
        module UiControllerTranslationPopup
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

          def handle_translate_action(action_data)
            selected_text = translation_text_for(action_data)
            return reject_translation('No text selected for translation') if selected_text.nil? || selected_text.empty?
            return reject_translation('Translator service is unavailable') unless @translation_service

            result = @translation_service.translate(selected_text, source_lang: 'auto', target_lang: 'en')
            show_translation_popup(result)
          end

          def close_translation_popup
            popup = current_translation_popup
            popup&.hide
            @reader_session_mutator.update_reader(translation_popup: nil)
            @reader_session_mutator.clear_selection
            :handled
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.translation_popup_close_failed', error: e.class.name, message: e.message)
            pass_input_result
          end

          def translation_popup_visible?
            current_translation_popup&.visible? == true
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.translation_popup_visibility_failed', error: e.class.name, message: e.message)
            visibility_fallback?
          end

          def handle_translation_popup_input(keys)
            return :pass unless translation_popup_visible?

            Array(keys).each do |key|
              return close_translation_popup if cancel_key?(key)

              scroll_translation_popup(-1) if up_key?(key)
              scroll_translation_popup(1) if down_key?(key)
            end

            :handled
          end

          def refresh_translation_popup_theme(theme_context:)
            color_mode = theme_context&.color_mode
            popup = current_translation_popup
            popup.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
          rescue Shoko::Error => e
            @logger&.debug(
              'ui_controller.translation_popup_theme_refresh_failed',
              error: e.class.name,
              message: e.message
            )
            ignored_refresh
          end

          private

          def show_translation_popup(result)
            popup = current_translation_popup || @ui_component_factory&.translation_popup
            return reject_translation('Translator popup is unavailable') unless popup

            popup.show(result)
            @reader_session_mutator.update_reader(translation_popup: popup, popup_menu: nil)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.translation_popup_failed', error: e.message)
            reject_translation(e.message)
          end

          def translation_text_for(action_data)
            selection_range = translation_selection_range(action_data)
            return nil unless selection_range && @selection_service && @rendered_content_reader

            text = @selection_service.extract_text(selection_range, @rendered_content_reader.rendered_lines)
            cleaned = text.to_s.strip.gsub(/\s+/, ' ')
            cleaned.empty? ? nil : cleaned
          end

          def translation_selection_range(action_data)
            return @reader_state.selection unless action_data.is_a?(Hash)

            action_data.dig(:data, :selection_range) || @reader_state.selection
          end

          def current_translation_popup
            return nil unless @reader_state.respond_to?(:translation_popup)

            @reader_state.translation_popup
          end

          def scroll_translation_popup(delta)
            popup = current_translation_popup
            return unless popup

            delta.negative? ? popup.scroll_up : popup.scroll_down
          end

          def reject_translation(message)
            set_message(message)
            @reader_session_mutator.update_reader(popup_menu: nil)
            :pass
          end

          def cancel_key?(key)
            keys = Shoko::Shared::KeyDefinitions::ACTIONS
            keys[:cancel].include?(key) || keys[:quit].include?(key)
          end

          def up_key?(key)
            Shoko::Shared::KeyDefinitions::NAVIGATION[:up].include?(key)
          end

          def down_key?(key)
            Shoko::Shared::KeyDefinitions::NAVIGATION[:down].include?(key)
          end

          def pass_input_result
            :pass
          end

          def visibility_fallback?
            false
          end

          def ignored_refresh
            nil
          end
        end
      end
    end
  end
end
