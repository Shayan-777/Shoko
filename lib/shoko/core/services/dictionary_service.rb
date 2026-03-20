# frozen_string_literal: true

require_relative 'base_service'
require_relative 'dictionary_service/search_support'
require_relative '../models/dictionary_entry'
require_relative '../ports/outbound/dictionary_repository'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Services
      # Domain service for dictionary lookups with dependency injection.
      # Provides word lookup, fuzzy search, and language pair management.
      class DictionaryService < BaseService
        include DictionaryServiceSearchSupport

        SearchRequest = Data.define(:query, :source, :target, :limit)
        DEFAULT_SOURCE_LANG = 'de'
        DEFAULT_TARGET_LANG = 'en'
        FRIENDLY_ERROR_MESSAGES = {
          corrupt_data: 'Dictionary database is corrupted. Reinstall the dictionary file.',
          invalid_data: 'Dictionary database is invalid. Reinstall the dictionary file.',
          permission_denied: 'Dictionary database is not readable.',
          unavailable: 'Dictionary backend is unavailable.',
        }.freeze

        def initialize(dictionary_repository: nil, config_reader: nil, logger: nil)
          super(logger: logger)
          @dictionary_repository = dictionary_repository
          @config_reader = config_reader
        end

        # Look up a word in the dictionary
        #
        # @param word [String] The word to look up
        # @param source_lang [String, nil] Source language (uses default if nil)
        # @param target_lang [String, nil] Target language (uses default if nil)
        # @param mode [Symbol] Search mode (:exact, :partial, :fuzzy, :grouped)
        # @param limit [Integer] Maximum results
        # @return [Models::DictionaryResult]
        def lookup(word, source_lang: nil, target_lang: nil, mode: :grouped, limit: 15)
          request = build_search_request(word, source_lang: source_lang, target_lang: target_lang, limit: limit)
          return empty_result(word) unless request
          return unavailable_result(word, request.source, request.target) unless repository_available_for?(request)

          raw_results = repository_search(request, mode: mode)
          build_result(word, raw_results, request, mode)
        rescue Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError => e
          log_error('dictionary_lookup_failed', word: word, code: e.code, error: e.message)
          error_result(word, e.code)
        rescue ArgumentError, TypeError => e
          log_error('dictionary_lookup_failed', word: word, error: e.message)
          error_result(word, :internal)
        end

        # Perform fuzzy search for similar words
        #
        # @param word [String] The word to search
        # @param source_lang [String, nil] Source language
        # @param target_lang [String, nil] Target language
        # @param limit [Integer] Maximum results
        # @return [Array<Models::FuzzyMatch>]
        def fuzzy_search(word, source_lang: nil, target_lang: nil, limit: 30)
          fuzzy_matches_for(
            word,
            source_lang: source_lang,
            target_lang: target_lang,
            limit: limit,
            translations: false,
            log_event: 'dictionary_fuzzy_search_failed'
          )
        end

        def fuzzy_search_translations(word, source_lang: nil, target_lang: nil, limit: 30)
          fuzzy_matches_for(
            word,
            source_lang: source_lang,
            target_lang: target_lang,
            limit: limit,
            translations: true,
            log_event: 'dictionary_fuzzy_search_translations_failed'
          )
        end

        # Check if dictionary service is available
        #
        # @return [Boolean]
        def available?
          return false unless @dictionary_repository

          @dictionary_repository.available_language_pairs.any?
        rescue Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError,
               ArgumentError => e
          logger.debug('dictionary.available? failed', error: e.message)
          false
        end

        # Get available language pairs
        #
        # @return [Array<Hash>] Array of {source:, target:} hashes
        def available_language_pairs
          return [] unless @dictionary_repository

          @dictionary_repository.available_language_pairs
        rescue Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError,
               ArgumentError => e
          logger.debug('dictionary.available_language_pairs failed', error: e.message)
          []
        end

        # Check if a specific language pair is available
        #
        # @param source_lang [String]
        # @param target_lang [String]
        # @return [Boolean]
        def language_pair_available?(source_lang, target_lang)
          return false unless @dictionary_repository

          @dictionary_repository.language_pair_available?(source_lang, target_lang)
        rescue Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError,
               ArgumentError => e
          logger.debug('dictionary.language_pair_available? failed', error: e.message)
          false
        end

        # Get configured or default source language
        def configured_source_lang
          value = @config_reader&.dictionary_source_lang
          value = value.to_s.strip if value
          value = nil if value.nil? || value.empty? || value.casecmp('auto').zero?
          value || DEFAULT_SOURCE_LANG
        rescue ArgumentError, TypeError => e
          logger.debug('dictionary.configured_source_lang failed', error: e.message)
          DEFAULT_SOURCE_LANG
        end

        # Get configured or default target language
        def configured_target_lang
          value = @config_reader&.dictionary_target_lang
          value = value.to_s.strip if value
          value = nil if value.nil? || value.empty? || value.casecmp('auto').zero?
          value || DEFAULT_TARGET_LANG
        rescue ArgumentError, TypeError => e
          logger.debug('dictionary.configured_target_lang failed', error: e.message)
          DEFAULT_TARGET_LANG
        end

        def normalize_language_setting(value)
          return nil if value.nil?

          str = value.to_s.strip
          return nil if str.empty? || str.casecmp('auto').zero?

          str
        end
        private :normalize_language_setting

        private

        def empty_result(word)
          Models::DictionaryResult.new(query: word.to_s, entries: [], search_mode: :exact)
        end

        def unavailable_result(word, source, target)
          Models::DictionaryResult.new(
            query: word.to_s,
            entries: [],
            source_lang: source,
            target_lang: target,
            search_mode: :unavailable
          )
        end

        def error_result(word, code)
          Models::DictionaryResult.new(
            query: word.to_s,
            entries: [],
            search_mode: :error,
            error_message: friendly_error_message_for_code(code)
          )
        end

        def log_error(event, **data)
          logger.error(event, **data)
        rescue ArgumentError
          # Silently ignore logging failures
        end

        def friendly_error_message_for_code(code)
          FRIENDLY_ERROR_MESSAGES[code&.to_sym]
        end
        private :friendly_error_message_for_code
      end
    end
  end
end
