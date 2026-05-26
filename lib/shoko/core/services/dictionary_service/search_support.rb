# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Shared request/repository plumbing for dictionary lookups and fuzzy search.
      module DictionaryServiceSearchSupport
        private

        def build_search_request(word, source_lang:, target_lang:, limit:)
          query = normalized_query(word)
          return nil unless query

          DictionaryService::SearchRequest.new(
            query: query,
            source: resolve_source_lang(source_lang),
            target: resolve_target_lang(target_lang),
            limit: limit
          )
        end

        def normalized_query(word)
          query = word.to_s.strip
          query.empty? ? nil : query
        end

        def resolve_source_lang(value)
          normalize_language_setting(value) || configured_source_lang
        end

        def resolve_target_lang(value)
          normalize_language_setting(value) || configured_target_lang
        end

        def repository_available_for?(request)
          @dictionary_repository&.language_pair_available?(request.source, request.target)
        end

        def repository_search(request, mode:)
          @dictionary_repository.search(
            request.query,
            source_lang: request.source,
            target_lang: request.target,
            limit: request.limit,
            mode: mode
          )
        end

        def fuzzy_matches_for(word, source_lang:, target_lang:, limit:, translations:, log_event:)
          request = build_search_request(word, source_lang: source_lang, target_lang: target_lang, limit: limit)
          return [] unless request
          return [] unless repository_available_for?(request)

          raw_matches = repository_fuzzy_matches(request, translations: translations)
          normalize_fuzzy_matches(raw_matches)
        rescue Shoko::Error => e
          code = e.is_a?(Shoko::Core::Errors::DictionaryFailure) ? e.code : :internal
          log_error(log_event, word: word, code: code, error: e.message)
          []
        rescue ArgumentError, TypeError => e
          log_error(log_event, word: word, error: e.message)
          []
        end

        def normalize_fuzzy_matches(raw_matches)
          Array(raw_matches).map do |match|
            normalized = normalize_fuzzy_match(match)
            Models::FuzzyMatch.new(word: normalized[:word], similarity: normalized[:similarity] || 0.0)
          end
        end

        def repository_fuzzy_matches(request, translations:)
          if translations
            @dictionary_repository.fuzzy_search_translations(
              request.query,
              source_lang: request.source,
              target_lang: request.target,
              limit: request.limit
            )
          else
            @dictionary_repository.fuzzy_search(
              request.query,
              source_lang: request.source,
              target_lang: request.target,
              limit: request.limit
            )
          end
        end

        def normalize_fuzzy_match(match)
          Shoko::Shared::HashNormalizer.symbolize_keys(match) || {}
        end

        def build_result(word, raw_results, request, mode)
          entries = raw_results.filter_map { |result| Models::DictionaryEntry.from_hash(result) }
          Models::DictionaryResult.new(
            query: word,
            entries: entries,
            source_lang: request.source,
            target_lang: request.target,
            search_mode: mode
          )
        end
      end
    end
  end
end
