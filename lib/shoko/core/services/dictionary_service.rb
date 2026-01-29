# frozen_string_literal: true

require_relative 'base_service'
require_relative '../models/dictionary_entry'

module Shoko
  module Core
    module Services
      # Domain service for dictionary lookups with dependency injection.
      # Provides word lookup, fuzzy search, and language pair management.
      class DictionaryService < BaseService
        DEFAULT_SOURCE_LANG = 'de'
        DEFAULT_TARGET_LANG = 'en'

        # Look up a word in the dictionary
        #
        # @param word [String] The word to look up
        # @param source_lang [String, nil] Source language (uses default if nil)
        # @param target_lang [String, nil] Target language (uses default if nil)
        # @param mode [Symbol] Search mode (:exact, :partial, :fuzzy, :grouped)
        # @param limit [Integer] Maximum results
        # @return [Models::DictionaryResult]
        def lookup(word, source_lang: nil, target_lang: nil, mode: :grouped, limit: 15)
          return empty_result(word) if word.nil? || word.strip.empty?

          source = normalize_language_setting(source_lang) || configured_source_lang
          target = normalize_language_setting(target_lang) || configured_target_lang

          return unavailable_result(word, source, target) unless @dictionary_repository

          unless @dictionary_repository.language_pair_available?(source, target)
            return unavailable_result(word, source, target)
          end

          raw_results = @dictionary_repository.search(
            word.strip,
            source_lang: source,
            target_lang: target,
            mode: mode,
            limit: limit
          )

          build_result(word, raw_results, source, target, mode)
        rescue StandardError => e
          log_error('dictionary_lookup_failed', word: word, error: e.message)
          error_result(word, e.message)
        end

        # Perform fuzzy search for similar words
        #
        # @param word [String] The word to search
        # @param source_lang [String, nil] Source language
        # @param target_lang [String, nil] Target language
        # @param limit [Integer] Maximum results
        # @return [Array<Models::FuzzyMatch>]
        def fuzzy_search(word, source_lang: nil, target_lang: nil, limit: 30)
          return [] if word.nil? || word.strip.empty?

          source = normalize_language_setting(source_lang) || configured_source_lang
          target = normalize_language_setting(target_lang) || configured_target_lang

          return [] unless @dictionary_repository&.language_pair_available?(source, target)

          raw_matches = @dictionary_repository.fuzzy_search(
            word.strip,
            source_lang: source,
            target_lang: target,
            limit: limit
          )

          raw_matches.map do |match|
            Models::FuzzyMatch.new(
              word: match[:word] || match['word'],
              similarity: match[:similarity] || match['similarity'] || 0.0
            )
          end
        rescue StandardError => e
          log_error('dictionary_fuzzy_search_failed', word: word, error: e.message)
          []
        end

        # Check if dictionary service is available
        #
        # @return [Boolean]
        def available?
          return false unless @dictionary_repository

          @dictionary_repository.available_language_pairs.any?
        rescue StandardError => e
          logger.debug('dictionary.available? failed', error: e.message)
          false
        end

        # Get available language pairs
        #
        # @return [Array<Hash>] Array of {source:, target:} hashes
        def available_language_pairs
          return [] unless @dictionary_repository

          @dictionary_repository.available_language_pairs
        rescue StandardError => e
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
        rescue StandardError => e
          logger.debug('dictionary.language_pair_available? failed', error: e.message)
          false
        end

        # Get configured or default source language
        def configured_source_lang
          value = @config_reader&.dictionary_source_lang
          value = value.to_s.strip if value
          value = nil if value.nil? || value.empty? || value.casecmp('auto').zero?
          value || DEFAULT_SOURCE_LANG
        rescue StandardError => e
          logger.debug('dictionary.configured_source_lang failed', error: e.message)
          DEFAULT_SOURCE_LANG
        end

        # Get configured or default target language
        def configured_target_lang
          value = @config_reader&.dictionary_target_lang
          value = value.to_s.strip if value
          value = nil if value.nil? || value.empty? || value.casecmp('auto').zero?
          value || DEFAULT_TARGET_LANG
        rescue StandardError => e
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

        protected

        def required_dependencies
          []
        end

        def setup_service_dependencies
          @dictionary_repository = resolve_optional(:dictionary_repository)
          @config_reader = resolve_optional(:config_reader)
        end

        private

        def build_result(word, raw_results, source_lang, target_lang, mode)
          entries = raw_results.filter_map { |r| Models::DictionaryEntry.from_hash(r) }
          Models::DictionaryResult.new(
            query: word,
            entries: entries,
            source_lang: source_lang,
            target_lang: target_lang,
            search_mode: mode
          )
        end

        def empty_result(word)
          Models::DictionaryResult.new(
            query: word.to_s,
            entries: [],
            search_mode: :exact
          )
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

        def error_result(word, message)
          Models::DictionaryResult.new(
            query: word.to_s,
            entries: [],
            search_mode: :error,
            error_message: friendly_error_message(message)
          )
        end

        def log_error(event, **data)
          logger.error(event, **data)
        rescue StandardError
          # Silently ignore logging failures
        end

        def friendly_error_message(message)
          return nil if message.nil?

          msg = message.to_s.downcase
          if msg.include?('database disk image is malformed') || msg.include?('malformed')
            'Dictionary database is corrupted. Reinstall the dictionary file.'
          elsif msg.include?('file is not a database') || msg.include?('no such table')
            'Dictionary database is invalid. Reinstall the dictionary file.'
          elsif msg.include?('permission denied')
            'Dictionary database is not readable.'
          end
        end
        private :friendly_error_message
      end
    end
  end
end
