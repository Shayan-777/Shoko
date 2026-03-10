# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        # Query construction and candidate extraction for fuzzy dictionary search.
        module FuzzyQuerySupport
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
            {
              exact: ->(db, word, _query, limit) { simple_search(db, word, partial: false, limit: limit) },
              partial: ->(db, word, _query, limit) { simple_search(db, word, partial: true, limit: limit) },
              grouped: ->(db, word, _query, limit) { grouped_search(db, word, partial: false, limit: limit) },
              detailed: ->(db, word, _query, limit) { detailed_search(db, word, partial: false, limit: limit) },
              fuzzy: ->(db, _word, query, limit) { fuzzy_search_internal(db, query, limit: limit) },
            }.fetch(mode) do
              ->(db, word, _query, limit) { simple_search(db, word, partial: false, limit: limit) }
            end
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
            scored = score_candidates(query, candidates, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
            filter_and_sort_fuzzy(scored, normalized_limit, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
          end

          def fuzzy_search_translations_internal(db, word, limit:)
            query = normalize_query_word(word)
            return [] unless query

            normalized_limit = positive_limit_or_default(limit, default: 10)
            candidates = fetch_translation_fuzzy_candidates(db, query, limit: normalized_limit)
            scored = score_candidates(query, candidates, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
            filter_and_sort_fuzzy(scored, normalized_limit, similarity_threshold: FUZZY_SIMILARITY_THRESHOLD)
          end

          def fetch_fuzzy_candidates(db, word, limit:)
            lower_word = word.downcase
            tolerance = word.length <= 5 ? FUZZY_SHORT_WORD_TOLERANCE : FUZZY_LENGTH_TOLERANCE
            min_len = [word.length - tolerance, 1].max
            max_len = word.length + tolerance
            candidate_limit = fuzzy_candidate_limit(limit)
            merged = []
            seen = {}

            fuzzy_candidate_queries(
              lower_word,
              min_len: min_len,
              max_len: max_len,
              candidate_limit: candidate_limit
            ).each do |query|
              rows = db.execute(query[:sql], query[:params])
              append_unique_candidates!(merged, seen, rows, candidate_limit)
              break if merged.length >= candidate_limit
            end

            merged
          end

          def fetch_translation_fuzzy_candidates(db, word, limit:)
            lower_word = word.downcase
            tolerance = word.length <= 5 ? FUZZY_SHORT_WORD_TOLERANCE : FUZZY_LENGTH_TOLERANCE
            min_len = [word.length - tolerance, 1].max
            max_len = word.length + tolerance
            candidate_limit = fuzzy_candidate_limit(limit)
            merged = []
            seen = {}

            translation_candidate_queries(lower_word, candidate_limit: candidate_limit).each do |query|
              rows = db.execute(query[:sql], query[:params])
              append_translation_candidates!(
                merged,
                seen,
                rows,
                word: lower_word,
                min_len: min_len,
                max_len: max_len,
                limit: candidate_limit
              )
              break if merged.length >= candidate_limit
            end

            merged
          end

          def fuzzy_candidate_queries(lower_word, min_len:, max_len:, candidate_limit:)
            queries = prefix_candidate_queries(lower_word, min_len: min_len, max_len: max_len, candidate_limit: candidate_limit)
            grams = fuzzy_query_grams(lower_word)
            unless grams.empty?
              queries << ngram_candidate_query(lower_word, grams, min_len: min_len, max_len: max_len,
                                               candidate_limit: candidate_limit)
            end
            queries << fallback_candidate_query(lower_word, min_len: min_len, max_len: max_len,
                                                candidate_limit: candidate_limit)
            queries
          end

          def prefix_candidate_queries(lower_word, min_len:, max_len:, candidate_limit:)
            FUZZY_PREFIX_LENGTHS.filter_map do |prefix_length|
              next if lower_word.length < prefix_length

              prefix = lower_word[0, prefix_length]
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
                params: [min_len, max_len, "#{prefix}%", lower_word.length, candidate_limit],
              }
            end
          end

          def fuzzy_query_grams(lower_word)
            return [] if lower_word.length < 3

            midpoint = [lower_word.length / 2 - 1, 0].max
            [lower_word[0, 3], lower_word[midpoint, 3], lower_word[-3, 3]]
              .map(&:to_s)
              .select { |gram| gram.length >= 3 }
              .uniq
          end

          def ngram_candidate_query(lower_word, grams, min_len:, max_len:, candidate_limit:)
            case_clauses = Array.new(grams.length, 'CASE WHEN lower(written_rep) LIKE ? THEN 1 ELSE 0 END').join(' + ')
            where_clauses = Array.new(grams.length, 'lower(written_rep) LIKE ?').join(' OR ')
            patterns = grams.map { |gram| "%#{gram}%" }

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
            queries = FUZZY_PREFIX_LENGTHS.filter_map do |prefix_length|
              next if lower_word.length < prefix_length

              fragment = lower_word[0, prefix_length]
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

            grams = fuzzy_query_grams(lower_word)
            unless grams.empty?
              where_clauses = Array.new(grams.length, 'lower(trans_list) LIKE ?').join(' OR ')
              patterns = grams.map { |gram| "%#{gram}%" }
              queries << {
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

            queries
          end

          def append_unique_candidates!(merged, seen, rows, limit)
            Array(rows).each do |row|
              token = row['written_rep'].to_s
              next if token.empty? || seen[token]

              seen[token] = true
              merged << row
              break if merged.length >= limit
            end
          end

          def append_translation_candidates!(merged, seen, rows, word:, min_len:, max_len:, limit:)
            Array(rows).each do |row|
              translation_candidates_from_row(row, word: word, min_len: min_len, max_len: max_len).each do |candidate|
                token = candidate['written_rep'].to_s
                downcased = token.downcase
                next if token.empty? || seen[downcased]

                seen[downcased] = true
                merged << candidate
                break if merged.length >= limit
              end
              break if merged.length >= limit
            end
          end

          def translation_candidates_from_row(row, word:, min_len:, max_len:)
            tokens = tokenize_translation_list(row['trans_list'] || row[:trans_list])
            importance = row['rel_importance'] || row[:rel_importance] || row['importance'] || row[:importance]
            score = row['max_score'] || row[:max_score] || row['score'] || row[:score]

            tokens.filter_map do |token|
              next unless token.length.between?(min_len, max_len)
              next unless translation_candidate_relevant?(word, token)

              {
                'written_rep' => token,
                'rel_importance' => importance,
                'max_score' => score,
              }
            end
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
        end
      end
    end
  end
end
