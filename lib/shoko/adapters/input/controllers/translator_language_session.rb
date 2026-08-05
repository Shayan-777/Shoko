# frozen_string_literal: true

require 'shoko/core/services/language_directory'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Owns asynchronous language-catalog loading and one deferred
        # translation waiting on that catalog.
        class TranslatorLanguageSession
          LanguageDirectory = Shoko::Core::Services::LanguageDirectory

          def initialize(reader_state:, translator_ui_session:, translation_service:, async_relay:,
                         on_message:, on_pending_translation:)
            @reader_state = reader_state
            @translator_ui_session = translator_ui_session
            @translation_service = translation_service
            @async_relay = async_relay
            @on_message = on_message
            @on_pending_translation = on_pending_translation
            @generation = 0
            @loading = false
            @loaded_languages = []
            @pending_translation = nil
          end

          def available?
            Array(@reader_state.translator_languages).any? || @loaded_languages.any?
          end

          def defer_translation(text:, announce:)
            @pending_translation = { text: text, announce: announce }
          end

          def clear_pending
            @pending_translation = nil
          end

          def ensure_loaded
            return if Array(@reader_state.translator_languages).any?
            return if @loading

            @loading = true
            request_id = next_request_id
            submitted = @async_relay.submit { fetch_languages(request_id) }
            return if submitted

            @loading = false
            message('Language worker is unavailable', 3)
          end

          private

          def fetch_languages(request_id)
            languages = @translation_service.available_languages.map(&:to_h)
            @async_relay.enqueue { publish_languages(languages, request_id) }
          rescue Shoko::Error => e
            @async_relay.enqueue { publish_error(e, request_id) }
          end

          def publish_languages(languages, request_id)
            return unless current_request?(request_id)

            @loading = false
            @loaded_languages = languages
            @translator_ui_session.apply_languages(languages)
            normalize_pair(languages)
            if languages.any?
              publish_pending_translation
            else
              clear_pending
              message('No translation languages are available', 3)
            end
          end

          def publish_error(error, request_id)
            return unless current_request?(request_id)

            @loading = false
            clear_pending
            message("Languages unavailable — #{error.message}", 3)
          end

          def publish_pending_translation
            pending = @pending_translation
            clear_pending
            @on_pending_translation.call(pending[:text], announce: pending[:announce]) if pending
          end

          def normalize_pair(languages)
            source_candidates = language_candidates(languages, side: :source)
            return if source_candidates.empty?

            source = valid_source(source_candidates)
            targets = language_candidates(languages, side: :target, source_code: source)
            target = valid_target(targets)
            @translator_ui_session.apply_pair(source: source, target: target) if target
          end

          def language_candidates(languages, side:, source_code: nil)
            LanguageDirectory.candidates_for(
              languages, side: side, source_code: source_code, query: ''
            )
          end

          def valid_source(candidates)
            current = @reader_state.translator_source_lang.to_s
            return current if candidates.any? { |item| item[:code] == current }

            candidates.first[:code]
          end

          def valid_target(candidates)
            current = @reader_state.translator_target_lang.to_s
            return current if candidates.any? { |item| item[:code] == current }

            candidates.first&.fetch(:code, nil)
          end

          def next_request_id
            @generation += 1
          end

          def current_request?(request_id)
            request_id == @generation
          end

          def message(text, duration)
            @on_message.call(text, duration)
          end
        end
      end
    end
  end
end
