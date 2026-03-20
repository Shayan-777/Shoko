# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        module FuzzyQuerySupport
          # Builds SQL fragments and query sets for fuzzy dictionary candidate selection.
          module CandidateQuerySets
            private

            def fuzzy_candidate_queries(lower_word, min_len:, max_len:, candidate_limit:)
              queries = prefix_candidate_queries(lower_word,
                                                 min_len: min_len,
                                                 max_len: max_len,
                                                 candidate_limit: candidate_limit)
              append_ngram_candidate_query!(queries,
                                            lower_word,
                                            min_len: min_len,
                                            max_len: max_len,
                                            candidate_limit: candidate_limit)
              queries << fallback_candidate_query(lower_word,
                                                  min_len: min_len,
                                                  max_len: max_len,
                                                  candidate_limit: candidate_limit)
              queries
            end

            def prefix_candidate_queries(lower_word, min_len:, max_len:, candidate_limit:)
              FUZZY_PREFIX_LENGTHS.filter_map do |prefix_length|
                prefix = query_prefix(lower_word, prefix_length)
                next unless prefix

                build_prefix_candidate_query(
                  prefix: prefix,
                  word_length: lower_word.length,
                  min_len: min_len,
                  max_len: max_len,
                  candidate_limit: candidate_limit
                )
              end
            end

            def fuzzy_query_grams(lower_word)
              return [] if lower_word.length < 3

              midpoint = [(lower_word.length / 2) - 1, 0].max
              [lower_word[0, 3], lower_word[midpoint, 3], lower_word[-3, 3]]
                .map(&:to_s)
                .select { |gram| gram.length >= 3 }
                .uniq
            end

            def ngram_candidate_query(lower_word, grams, min_len:, max_len:, candidate_limit:)
              return nil if grams.empty?

              case_clauses, where_clauses, patterns = ngram_query_fragments(grams, 'written_rep')
              build_ngram_candidate_query(
                case_clauses: case_clauses,
                where_clauses: where_clauses,
                patterns: patterns,
                lower_word: lower_word,
                min_len: min_len,
                max_len: max_len,
                candidate_limit: candidate_limit
              )
            end

            def build_ngram_candidate_query(case_clauses:, where_clauses:, patterns:, lower_word:, min_len:, max_len:,
                                            candidate_limit:)
              {
                sql: <<~SQL,
                  SELECT written_rep, max_score, rel_importance,
                         (#{case_clauses}) AS gram_hits
                  FROM simple_translation
                  WHERE length(written_rep) BETWEEN ? AND ?
                  AND (#{where_clauses})
                  ORDER BY gram_hits DESC,
                           ABS(length(written_rep) - ?) ASC,
                           rel_importance DESC,
                           max_score DESC,
                           lower(written_rep) ASC
                  LIMIT ?
                SQL
                params: patterns + [min_len, max_len] + patterns + [lower_word.length, candidate_limit],
              }
            end

            def fallback_candidate_query(lower_word, min_len:, max_len:, candidate_limit:)
              {
                sql: <<~SQL,
                  SELECT written_rep, max_score, rel_importance
                  FROM simple_translation
                  WHERE length(written_rep) BETWEEN ? AND ?
                  ORDER BY ABS(length(written_rep) - ?) ASC,
                           rel_importance DESC,
                           max_score DESC,
                           lower(written_rep) ASC
                  LIMIT ?
                SQL
                params: [min_len, max_len, lower_word.length, candidate_limit],
              }
            end

            def translation_candidate_queries(lower_word, candidate_limit:)
              translation_prefix_candidate_queries(lower_word, candidate_limit).tap do |queries|
                ngram_query = translation_ngram_candidate_query(lower_word, candidate_limit)
                queries << ngram_query if ngram_query
              end
            end

            def append_ngram_candidate_query!(queries, lower_word, min_len:, max_len:, candidate_limit:)
              ngram_query = ngram_candidate_query(
                lower_word,
                fuzzy_query_grams(lower_word),
                min_len: min_len,
                max_len: max_len,
                candidate_limit: candidate_limit
              )
              queries << ngram_query if ngram_query
            end

            def query_prefix(lower_word, prefix_length)
              return nil if lower_word.length < prefix_length

              lower_word[0, prefix_length]
            end

            def build_prefix_candidate_query(prefix:, word_length:, min_len:, max_len:, candidate_limit:)
              {
                sql: <<~SQL,
                  SELECT written_rep, max_score, rel_importance
                  FROM simple_translation
                  WHERE length(written_rep) BETWEEN ? AND ?
                  AND lower(written_rep) LIKE ?
                  ORDER BY ABS(length(written_rep) - ?) ASC,
                           rel_importance DESC,
                           max_score DESC,
                           lower(written_rep) ASC
                  LIMIT ?
                SQL
                params: [min_len, max_len, "#{prefix}%", word_length, candidate_limit],
              }
            end

            def translation_prefix_candidate_queries(lower_word, candidate_limit)
              FUZZY_PREFIX_LENGTHS.filter_map do |prefix_length|
                fragment = query_prefix(lower_word, prefix_length)
                next unless fragment

                build_translation_prefix_query(fragment, candidate_limit)
              end
            end

            def build_translation_prefix_query(fragment, candidate_limit)
              {
                sql: <<~SQL,
                  SELECT written_rep, trans_list, score AS max_score, importance AS rel_importance
                  FROM translation_grouped
                  WHERE lower(trans_list) LIKE ?
                  ORDER BY importance DESC, score DESC, lower(written_rep) ASC
                  LIMIT ?
                SQL
                params: ["%#{fragment}%", candidate_limit],
              }
            end

            def translation_ngram_candidate_query(lower_word, candidate_limit)
              grams = fuzzy_query_grams(lower_word)
              return nil if grams.empty?

              _case_clauses, where_clauses, patterns = ngram_query_fragments(grams, 'trans_list')
              {
                sql: <<~SQL,
                  SELECT written_rep, trans_list, score AS max_score, importance AS rel_importance
                  FROM translation_grouped
                  WHERE #{where_clauses}
                  ORDER BY importance DESC, score DESC, lower(written_rep) ASC
                  LIMIT ?
                SQL
                params: patterns + [candidate_limit],
              }
            end

            def ngram_query_fragments(grams, field)
              case_clause = "CASE WHEN lower(#{field}) LIKE ? THEN 1 ELSE 0 END"
              where_clause = "lower(#{field}) LIKE ?"
              patterns = grams.map { |gram| "%#{gram}%" }

              [
                Array.new(grams.length, case_clause).join(' + '),
                Array.new(grams.length, where_clause).join(' OR '),
                patterns,
              ]
            end
          end
        end
      end
    end
  end
end
