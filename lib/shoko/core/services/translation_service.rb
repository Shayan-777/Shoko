# frozen_string_literal: true

require_relative 'base_service'
require_relative '../models/translation_result'
require_relative '../errors/translation_failure'

module Shoko
  module Core
    module Services
      # Domain service for text translation over an injected backend.
      class TranslationService < BaseService
        DEFAULT_SOURCE_LANG = 'auto'
        DEFAULT_TARGET_LANG = 'en'
        UNAVAILABLE_MESSAGE = 'Translator service is unavailable.'

        def initialize(translation_repository: nil, logger: nil)
          super(logger: logger)
          @translation_repository = translation_repository
        end

        def available_languages
          return [] unless @translation_repository

          @translation_repository.available_languages
        rescue Shoko::Core::Errors::TranslationFailure => e
          logger.debug('translation.available_languages_failed', code: repository_error_code(e), error: e.message)
          raise
        end

        def translate(text, source_lang: DEFAULT_SOURCE_LANG, target_lang: DEFAULT_TARGET_LANG)
          query = text.to_s.strip
          source = normalized_source_lang(source_lang)
          target = normalized_target_lang(target_lang)
          return empty_result(source: source, target: target) if query.empty?
          unless @translation_repository
            return error_result(query, source: source, target: target, message: UNAVAILABLE_MESSAGE)
          end

          @translation_repository.translate(query, source_lang: source, target_lang: target)
        rescue Shoko::Core::Errors::TranslationFailure => e
          logger.error('translation.translate_failed', code: repository_error_code(e), error: e.message)
          error_result(query, source: source, target: target, message: e.message,
                              code: repository_error_code(e))
        end

        private

        def repository_error_code(error)
          error.code
        end

        def normalized_source_lang(value)
          lang = value.to_s.strip
          lang.empty? ? DEFAULT_SOURCE_LANG : lang
        end

        def normalized_target_lang(value)
          lang = value.to_s.strip
          lang.empty? ? DEFAULT_TARGET_LANG : lang
        end

        def empty_result(source:, target:)
          Shoko::Core::Models::TranslationResult.new(
            query: '',
            translated_text: '',
            source_lang: source,
            target_lang: target
          )
        end

        def error_result(query, source:, target:, message:, code: :internal)
          Shoko::Core::Models::TranslationResult.new(
            query: query,
            translated_text: '',
            source_lang: source,
            target_lang: target,
            error_message: message,
            error_code: code
          )
        end
      end
    end
  end
end
