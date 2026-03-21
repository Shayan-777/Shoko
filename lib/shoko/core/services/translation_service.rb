# frozen_string_literal: true

require_relative 'base_service'
require_relative '../models/translation_result'
require_relative '../ports/outbound/translation_repository'

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
        rescue Shoko::Core::Ports::Outbound::TranslationRepository::RepositoryError => e
          logger.debug('translation.available_languages_failed', code: e.code, error: e.message)
          []
        rescue Shoko::Error => e
          logger.debug('translation.available_languages_failed', error: e.message)
          []
        end

        def translate(text, source_lang: DEFAULT_SOURCE_LANG, target_lang: DEFAULT_TARGET_LANG)
          query = text.to_s.strip
          source = normalized_source_lang(source_lang)
          target = normalized_target_lang(target_lang)
          return empty_result(source: source, target: target) if query.empty?
          return error_result(query, source: source, target: target, message: UNAVAILABLE_MESSAGE) unless @translation_repository

          @translation_repository.translate(query, source_lang: source, target_lang: target)
        rescue Shoko::Core::Ports::Outbound::TranslationRepository::RepositoryError => e
          logger.error('translation.translate_failed', code: e.code, error: e.message)
          error_result(query, source: source, target: target, message: e.message)
        rescue Shoko::Error => e
          logger.error('translation.translate_failed', error: e.message)
          error_result(query, source: source, target: target, message: e.message)
        end

        private

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

        def error_result(query, source:, target:, message:)
          Shoko::Core::Models::TranslationResult.new(
            query: query,
            translated_text: '',
            source_lang: source,
            target_lang: target,
            error_message: message
          )
        end
      end
    end
  end
end
