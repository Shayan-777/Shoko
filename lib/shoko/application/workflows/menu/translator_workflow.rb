# frozen_string_literal: true

require_relative '../../use_cases/support/menu_session_access'
require_relative '../../services/async_result_relay'
require 'shoko/core/services/language_directory'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side translation requests and transient translator state.
        #
        # Backend calls run through an AsyncResultRelay so a slow backend (a
        # first model load, or an unreachable LibreTranslate server) cannot
        # freeze the menu; results are applied on the menu thread when the
        # relay drains. Without a relay executor the workflow stays fully
        # synchronous.
        class TranslatorWorkflow
          TranslationRequest = Data.define(:query, :source_lang, :target_lang, :request_id)

          include Shoko::Application::UseCases::Support::MenuSessionAccess

          def initialize(translation_service:, menu_session_store:, menu_transient_store:, async_relay: nil,
                         logger: nil)
            raise ArgumentError, 'translation_service is required' if translation_service.nil?

            assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
            @translation_service = translation_service
            @async_relay = async_relay || Shoko::Application::Services::AsyncResultRelay.new(logger: logger)
            @logger = logger
            @request_generation = 0
            @language_generation = 0
            @languages_loading = false
            @pending_translation = nil
          end

          def fetch_languages(force: false)
            return cached_languages if cached_languages.any? && !force
            return cached_languages if @languages_loading

            @languages_loading = true
            request_id = next_language_request_id
            update_translator_state(translator_status: :loading, translator_message: 'Loading languages...')
            submitted = @async_relay.submit { perform_language_fetch(request_id) }
            unless submitted
              @languages_loading = false
              update_translator_state(translator_status: :error,
                                      translator_message: 'Language worker is unavailable.')
            end
            cached_languages
          end

          def translate_text(text:, source_lang:, target_lang:)
            query = text.to_s
            return clear_translation if query.strip.empty?

            if cached_languages.empty?
              @pending_translation = query
              fetch_languages
              return nil
            end

            update_translator_state(translator_status: :working, translator_message: 'Translating...')
            request = TranslationRequest.new(query:, source_lang:, target_lang:, request_id: next_request_id)
            submitted = @async_relay.submit { perform_translation(request) }
            unless submitted
              update_translator_state(translator_status: :error,
                                      translator_message: 'Translation worker is unavailable.')
            end
            nil
          end

          # Applies any results the worker produced; called from the menu loop
          # on the UI thread.
          def process_pending_events
            @async_relay.drain!
          end

          def network_pending?
            @async_relay.busy?
          end

          private

          # ----- worker-side network jobs (no state writes; enqueue only) -----

          def perform_language_fetch(request_id)
            languages = @translation_service.available_languages.map(&:to_h)
            @async_relay.enqueue { publish_languages(languages, request_id) }
          rescue Shoko::Error => e
            @async_relay.enqueue { publish_language_error(e, request_id) }
          end

          def perform_translation(request)
            result = @translation_service.translate(
              request.query, source_lang: request.source_lang, target_lang: request.target_lang
            )
            @async_relay.enqueue { publish_translation(result, request) }
          rescue Shoko::Error => e
            @async_relay.enqueue { publish_translation_error(e, request) }
          end

          def publish_languages(languages, request_id)
            return unless current_language_request?(request_id)

            @languages_loading = false
            payload = {
              translator_languages: languages,
              translator_status: :ready,
              translator_message: language_message(languages),
            }.merge(normalized_pair_payload(languages))
            update_translator_state(payload)
            submit_pending_translation if languages.any?
          end

          def publish_language_error(error, request_id)
            return unless current_language_request?(request_id)

            @languages_loading = false
            @pending_translation = nil
            log_error('translator.fetch_languages_failed', error)
            update_translator_state(translator_languages: [], translator_status: :error,
                                    translator_message: error.message)
          end

          def publish_translation(result, request)
            return unless translation_request_current?(request)

            update_translator_state(translation_payload(result))
          end

          def publish_translation_error(error, request)
            return unless translation_request_current?(request)

            log_error('translator.translate_failed', error)
            update_translator_state(
              translator_status: :error, translator_message: error.message, translator_output_text: ''
            )
          end

          def translation_request_current?(request)
            translation_context_current?(
              request.request_id, request.query, request.source_lang, request.target_lang
            )
          end

          def cached_languages
            Array(current_menu.translator_languages)
          end

          def clear_translation
            next_request_id
            update_translator_state(
              translator_output_text: '',
              translator_detected_source_lang: nil,
              translator_status: :idle,
              translator_message: 'Type text to translate.',
              translator_output_scroll: 0
            )
          end

          def translation_payload(result)
            {
              translator_output_text: result.translated_text,
              translator_detected_source_lang: result.detected_source_lang,
              translator_status: result.error? ? :error : :done,
              translator_message: result.error? ? result.error_message : success_message(result),
              translator_output_scroll: 0,
            }
          end

          def success_message(result)
            source = result.detected_source_lang || result.source_lang
            route = result.route.length > 2 ? " via #{result.route[1]}" : ''
            suffix = result.truncated? ? ' · output limit reached' : ''
            "Translated #{source} -> #{result.target_lang}#{route}#{suffix}"
          end

          def language_message(languages)
            count = languages.length
            count.positive? ? "#{count} languages available." : 'No languages available.'
          end

          def normalized_pair_payload(languages)
            source_options = Shoko::Core::Services::LanguageDirectory.candidates_for(
              languages, side: :source, source_code: nil, query: ''
            )
            return {} if source_options.empty?

            source = normalized_source_code(source_options)
            target = normalized_target_code(languages, source)
            { translator_source_lang: source, translator_target_lang: target }
          end

          def normalized_source_code(source_options)
            current = current_menu.translator_source_lang.to_s
            source_options.any? { |item| item[:code] == current } ? current : source_options.first[:code]
          end

          def normalized_target_code(languages, source)
            targets = Shoko::Core::Services::LanguageDirectory.candidates_for(
              languages, side: :target, source_code: source, query: ''
            )
            current = current_menu.translator_target_lang.to_s
            targets.any? { |item| item[:code] == current } ? current : targets.first[:code]
          end

          def next_request_id
            @request_generation += 1
          end

          def translation_context_current?(request_id, query, source, target)
            request_id == @request_generation &&
              current_menu.translator_input_text.to_s == query.to_s &&
              current_menu.translator_source_lang.to_s == source.to_s &&
              current_menu.translator_target_lang.to_s == target.to_s
          end

          def next_language_request_id
            @language_generation += 1
          end

          def current_language_request?(request_id)
            request_id == @language_generation
          end

          def submit_pending_translation
            query = @pending_translation
            @pending_translation = nil
            return unless query

            translate_text(
              text: query,
              source_lang: current_menu.translator_source_lang,
              target_lang: current_menu.translator_target_lang
            )
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
