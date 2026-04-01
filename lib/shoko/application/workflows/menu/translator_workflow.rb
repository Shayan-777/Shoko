# frozen_string_literal: true

require_relative '../../use_cases/support/menu_session_access'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side translation requests and transient translator state.
        class TranslatorWorkflow
          include Shoko::Application::UseCases::Support::MenuSessionAccess

          def initialize(translation_service:, menu_session_store:, menu_transient_store:, logger: nil)
            raise ArgumentError, 'translation_service is required' if translation_service.nil?

            assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
            @translation_service = translation_service
            @logger = logger
          end

          def fetch_languages(force: false)
            return cached_languages if cached_languages.any? && !force

            update_translator_state(translator_status: :loading, translator_message: 'Loading languages...')
            languages = @translation_service.available_languages.map(&:to_h)
            update_translator_state(
              translator_languages: languages,
              translator_status: :ready,
              translator_message: language_message(languages)
            )
            languages
          rescue Shoko::Error => e
            log_error('translator.fetch_languages_failed', e)
            update_translator_state(translator_languages: [], translator_status: :error, translator_message: e.message)
            []
          end

          def translate_text(text:, source_lang:, target_lang:)
            query = text.to_s
            return clear_translation if query.strip.empty?

            update_translator_state(translator_status: :working, translator_message: 'Translating...')
            result = @translation_service.translate(query, source_lang: source_lang, target_lang: target_lang)
            update_translator_state(translation_payload(result))
            result
          rescue Shoko::Error => e
            log_error('translator.translate_failed', e)
            update_translator_state(
              translator_status: :error,
              translator_message: e.message,
              translator_output_text: ''
            )
            nil
          end

          private

          def cached_languages
            Array(current_menu.translator_languages)
          end

          def clear_translation
            update_translator_state(
              translator_output_text: '',
              translator_detected_source_lang: nil,
              translator_status: :idle,
              translator_message: 'Type text to translate.'
            )
          end

          def translation_payload(result)
            {
              translator_output_text: result.translated_text,
              translator_detected_source_lang: result.detected_source_lang,
              translator_status: result.error? ? :error : :done,
              translator_message: result.error? ? result.error_message : success_message(result),
            }
          end

          def success_message(result)
            source = result.detected_source_lang || result.source_lang
            "Translated #{source} -> #{result.target_lang}"
          end

          def language_message(languages)
            count = languages.length
            count.positive? ? "#{count} languages available." : 'No languages available.'
          end

          def update_translator_state(payload)
            update_menu(
              {
                translator_selection: nil,
                translator_context_menu: nil,
              }.merge(payload)
            )
          end

          def log_error(event, error)
            @logger&.error(event, error: error.class.name, message: error.message)
          end
        end
      end
    end
  end
end
