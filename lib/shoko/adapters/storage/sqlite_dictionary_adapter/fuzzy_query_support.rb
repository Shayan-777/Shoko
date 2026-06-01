# frozen_string_literal: true

require_relative '../../../shared/hash_normalizer'
require_relative 'fuzzy_ranker'
require_relative 'fuzzy_query_support/candidate_query_sets'
require_relative 'fuzzy_query_support/candidate_row_support'

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        # Query construction and candidate extraction for fuzzy dictionary search.
        module FuzzyQuerySupport
          include CandidateQuerySets
          include CandidateRowSupport

          SEARCH_HANDLERS = {
            exact: :run_exact_search,
            partial: :run_partial_search,
            grouped: :run_grouped_search,
            detailed: :run_detailed_search,
            fuzzy: :run_fuzzy_search,
          }.freeze

          private

          def simple_search(db, word, partial:, limit:)
            query = build_search_query('translation_grouped',
                                       'written_rep, sense_list, trans_list, score, importance',
                                       partial: partial)
            search_term = partial ? "%#{word}%" : word
            params = partial ? [search_term, limit] : [search_term]

            db.execute(query, params)
          end

          def grouped_search(db, word, partial:, limit:)
            query = build_search_query('translation_grouped', '*', partial: partial)
            search_term = partial ? "%#{word}%" : word
            params = partial ? [search_term, limit] : [search_term]

            db.execute(query, params)
          end

          def detailed_search(db, word, partial:, limit:)
            query = build_search_query('translation', '*', partial: partial)
            search_term = partial ? "%#{word}%" : word
            params = partial ? [search_term, limit] : [search_term]

            db.execute(query, params)
          end

          def perform_search(db, word:, mode:, query:, limit:)
            search_dispatch(mode).call(db, word, query, limit)
          end

          def search_dispatch(mode)
            method(SEARCH_HANDLERS.fetch(mode, :run_exact_search))
          end

          def build_search_query(table, columns, partial:)
            operator = partial ? 'LIKE' : '='
            limit_clause = partial ? 'LIMIT ?' : ''

            <<~SQL
              SELECT #{columns}
              FROM #{table}
              WHERE written_rep #{operator} ? COLLATE NOCASE
              ORDER BY score DESC, importance DESC
              #{limit_clause}
            SQL
          end

          def fuzzy_search_internal(db, word, limit:)
            query = normalize_query_word(word)
            return [] unless query

            normalized_limit = positive_limit_or_default(limit, default: 10)
            candidates = fetch_fuzzy_candidates(db, query, limit: normalized_limit)
            scored = FuzzyRanker.score_candidates(query, candidates, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
            FuzzyRanker.filter_and_sort_fuzzy(scored, normalized_limit, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
          end

          def fuzzy_search_translations_internal(db, word, limit:)
            query = normalize_query_word(word)
            return [] unless query

            normalized_limit = positive_limit_or_default(limit, default: 10)
            candidates = fetch_translation_fuzzy_candidates(db, query, limit: normalized_limit)
            scored = FuzzyRanker.score_candidates(query, candidates, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
            FuzzyRanker.filter_and_sort_fuzzy(scored, normalized_limit, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
          end

          def append_unique_candidates!(merged, seen, rows, limit)
            Array(rows).each do |row|
              normalized = FuzzyRanker.normalize_candidate_row(row)
              token = normalized[:written_rep].to_s
              next if token.empty? || seen[token]

              seen[token] = true
              merged << normalized
              break if merged.length >= limit
            end
          end

          def run_exact_search(db, word, _query, limit)
            simple_search(db, word, partial: false, limit: limit)
          end

          def run_partial_search(db, word, _query, limit)
            simple_search(db, word, partial: true, limit: limit)
          end

          def run_grouped_search(db, word, _query, limit)
            grouped_search(db, word, partial: false, limit: limit)
          end

          def run_detailed_search(db, word, _query, limit)
            detailed_search(db, word, partial: false, limit: limit)
          end

          def run_fuzzy_search(db, _word, query, limit)
            fuzzy_search_internal(db, query, limit: limit)
          end
        end
      end
    end
  end
end
