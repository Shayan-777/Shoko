# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        module FuzzyQuerySupport
          # Normalizes candidate rows and collects fuzzy candidates from SQL query batches.
          module CandidateRowSupport
            private

            def fetch_fuzzy_candidates(db, word, limit:)
              lower_word = word.downcase
              min_len, max_len = fuzzy_length_bounds(word)
              candidate_limit = fuzzy_candidate_limit(limit)
              queries = fuzzy_candidate_queries(lower_word, min_len: min_len, max_len: max_len,
                                                            candidate_limit: candidate_limit)

              collect_candidate_rows(db, queries, limit: candidate_limit) do |rows, merged, seen, row_limit|
                append_unique_candidates!(merged, seen, rows, row_limit)
              end
            end

            def fetch_translation_fuzzy_candidates(db, word, limit:)
              lower_word = word.downcase
              min_len, max_len = fuzzy_length_bounds(word)
              candidate_limit = fuzzy_candidate_limit(limit)
              queries = translation_candidate_queries(lower_word, candidate_limit: candidate_limit)

              collect_candidate_rows(db, queries, limit: candidate_limit) do |rows, merged, seen, row_limit|
                append_translation_candidates!(
                  merged,
                  seen,
                  rows,
                  word: lower_word,
                  min_len: min_len,
                  max_len: max_len,
                  limit: row_limit
                )
              end
            end

            def append_translation_candidates!(merged, seen, rows, word:, min_len:, max_len:, limit:)
              Array(rows).each do |row|
                translation_candidates_from_row(row, word: word, min_len: min_len, max_len: max_len).each do |candidate|
                  token = candidate[:written_rep].to_s
                  key = token.downcase
                  next if token.empty? || seen[key]

                  seen[key] = true
                  merged << candidate
                  break if merged.length >= limit
                end
                break if merged.length >= limit
              end
            end

            def translation_candidates_from_row(row, word:, min_len:, max_len:)
              normalized = normalize_candidate_row(row)
              importance = normalized[:rel_importance] || normalized[:importance]
              score = normalized[:max_score] || normalized[:score]

              tokenize_translation_list(normalized[:trans_list]).filter_map do |token|
                next unless token.length.between?(min_len, max_len)
                next unless translation_candidate_relevant?(word, token)

                { written_rep: token, rel_importance: importance, max_score: score }
              end
            end

            def normalize_candidate_row(row)
              Shoko::Shared::HashNormalizer.symbolize_keys(row) || {}
            end

            def tokenize_translation_list(value)
              value.to_s
                   .split('|')
                   .flat_map { |segment| segment.to_s.unicode_normalize(:nfkc).scan(TRANSLATION_TOKEN) }
                   .map(&:strip)
                   .reject(&:empty?)
                   .uniq
            end

            def translation_candidate_relevant?(word, token)
              normalized_word = normalize_for_comparison(word)
              normalized_token = normalize_for_comparison(token)
              return false if normalized_word.empty? || normalized_token.empty?

              return true if normalized_token.start_with?(normalized_word[0, 2].to_s)
              return true if fuzzy_query_grams(normalized_word).any? { |gram| normalized_token.include?(gram) }

              ngram_similarity(normalized_word, normalized_token, 2) >= 0.35
            end

            def fuzzy_length_bounds(word)
              tolerance = word.length <= 5 ? FUZZY_SHORT_WORD_TOLERANCE : FUZZY_LENGTH_TOLERANCE
              [[word.length - tolerance, 1].max, word.length + tolerance]
            end

            def collect_candidate_rows(db, queries, limit:)
              merged = []
              seen = {}

              queries.each do |query|
                rows = db.execute(query[:sql], query[:params])
                yield(rows, merged, seen, limit)
                break if merged.length >= limit
              end

              merged
            end
          end
        end
      end
    end
  end
end
