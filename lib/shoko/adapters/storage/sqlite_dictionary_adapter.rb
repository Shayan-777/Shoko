# frozen_string_literal: true

require_relative '../../application/ports/outbound/dictionary_repository'
require_relative 'config_paths'
require_relative '../../shared/optional_dependency'
require_relative '../../shared/type_coercion'
require_relative 'sqlite_dictionary_adapter/fuzzy_ranker'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Adapters
    module Storage
      # SQLite adapter for dictionary database operations.
      class SqliteDictionaryAdapter
        include Application::Ports::Outbound::DictionaryRepository

        LANGUAGE_CODES = {
          'german' => 'de',
          'english' => 'en',
          'russian' => 'ru',
          'chinese' => 'zh',
          'de' => 'de',
          'en' => 'en',
          'ru' => 'ru',
          'zh' => 'zh',
        }.freeze

        FUZZY_LENGTH_TOLERANCE = 3
        FUZZY_SHORT_WORD_TOLERANCE = 2
        FUZZY_CANDIDATE_MULTIPLIER = 25
        FUZZY_CANDIDATE_FLOOR = 80
        FUZZY_CANDIDATE_LIMIT = 500
        FUZZY_SIMILARITY_THRESHOLD = 0.4
        FUZZY_PREFIX_LENGTHS = [3, 2, 1].freeze
        SQLITE_HEADER = "SQLite format 3\0"
        TRANSLATION_TOKEN = /\p{L}[\p{L}\p{M}\p{N}'’-]*/

        def initialize(databases_path: nil, logger: nil)
          @databases_path = resolve_databases_path(databases_path)
          @logger = logger
        end

        def search(word, source_lang:, target_lang:, mode: :exact, limit: 10)
          query = mode == :fuzzy ? normalize_query_word(word) : word
          return [] if mode == :fuzzy && query.nil?

          db_path = database_path_for(source_lang, target_lang)
          return [] unless valid_database_file?(db_path)

          with_connection(db_path) do |db|
            perform_search(db, word: word, mode: mode, query: query, limit: limit)
          end
        end

        def fuzzy_search(word, source_lang:, target_lang:, limit: 30)
          query = normalize_query_word(word)
          return [] unless query

          db_path = database_path_for(source_lang, target_lang)
          return [] unless valid_database_file?(db_path)

          with_connection(db_path) do |db|
            fuzzy_search_internal(db, query, limit: limit)
          end
        end

        def fuzzy_search_translations(word, source_lang:, target_lang:, limit: 30)
          query = normalize_query_word(word)
          return [] unless query

          db_path = database_path_for(source_lang, target_lang)
          return [] unless valid_database_file?(db_path)

          with_connection(db_path) do |db|
            fuzzy_search_translations_internal(db, query, limit: limit)
          end
        end

        def available_language_pairs
          return [] unless @databases_path && Dir.exist?(@databases_path)

          Dir.glob(File.join(@databases_path, '*.sqlite3')).filter_map do |path|
            basename = File.basename(path, '.sqlite3')
            parts = basename.split('-')
            next unless parts.length == 2
            next unless valid_database_file?(path)

            { source: parts[0], target: parts[1] }
          end
        end

        def language_pair_available?(source_lang, target_lang)
          path = database_path_for(source_lang, target_lang)
          valid_database_file?(path)
        end

        def database_path_for(source_lang, target_lang)
          source_code = normalize_lang_code(source_lang)
          target_code = normalize_lang_code(target_lang)
          return nil unless source_code && target_code

          File.join(@databases_path, "#{source_code}-#{target_code}.sqlite3")
        end

        def self.default_databases_path
          ConfigPaths.config_path('dictionary')
        end

        def self.databases_present?(databases_path = nil)
          path = if databases_path && !databases_path.to_s.strip.empty?
                   File.expand_path(databases_path.to_s)
                 else
                   default_databases_path
                 end
          return false unless path && Dir.exist?(path)

          Dir.glob(File.join(path, '*.sqlite3')).any?
        end

        def self.sqlite3_available?
          Shoko::Shared::OptionalDependency.require_gem!('sqlite3')
          true
        end

        SEARCH_HANDLERS = {
          exact: :run_exact_search,
          partial: :run_partial_search,
          grouped: :run_grouped_search,
          detailed: :run_detailed_search,
          fuzzy: :run_fuzzy_search,
        }.freeze

        private

        def resolve_databases_path(databases_path)
          if databases_path && !databases_path.to_s.strip.empty?
            File.expand_path(databases_path.to_s)
          else
            self.class.default_databases_path
          end
        end

        def normalize_lang_code(lang)
          LANGUAGE_CODES[lang&.downcase]
        end

        def with_connection(db_path)
          require_sqlite3!
          db = SQLite3::Database.new(db_path)
          db.results_as_hash = true
          begin
            yield db
          ensure
            db.close
          end
        rescue SQLite3::Exception => e
          log_error('sqlite_dictionary_error', path: db_path, error: e.message)
          raise Shoko::Application::Ports::Outbound::DictionaryRepository::RepositoryError.new(
            code: classify_sqlite_failure(e),
            message: e.message,
            details: { path: db_path, error_class: e.class.name }
          )
        end

        def valid_database_file?(path)
          return false if path.to_s.strip.empty?
          return false unless File.file?(path)
          return false unless File.readable?(path)
          return false unless File.size?(path)

          File.binread(path, SQLITE_HEADER.bytesize) == SQLITE_HEADER
        end

        def normalize_query_word(word)
          query = word.to_s.strip
          return nil if query.empty?

          query
        end

        # SQLite LIKE treats % and _ as wildcards; user-typed query text must
        # match literally, so wildcard characters (and the escape character
        # itself) are escaped and every LIKE carries an explicit ESCAPE clause.
        def escape_like(text)
          text.to_s.gsub(/[\\%_]/) { |char| "\\#{char}" }
        end

        def positive_limit_or_default(value, default:)
          num = value.to_i
          num.positive? ? num : default
        end

        def fuzzy_candidate_limit(limit)
          requested = positive_limit_or_default(limit, default: 10)
          scaled = [requested * FUZZY_CANDIDATE_MULTIPLIER, FUZZY_CANDIDATE_FLOOR].max
          [scaled, FUZZY_CANDIDATE_LIMIT].min
        end

        def log_error(event, **data)
          @logger&.error(event, **data)
        rescue Shoko::Error
          # Silently ignore logging failures at the adapter boundary.
        end

        def require_sqlite3!
          Shoko::Shared::OptionalDependency.require_gem!('sqlite3')
        rescue Shoko::DependencyUnavailableError => e
          raise Shoko::DependencyUnavailableError, <<~MSG
            Dictionary lookup requires the optional gem 'sqlite3'.

            Install:
              gem install sqlite3
            On Void Linux you may also need:
              sudo xbps-install -S sqlite-devel

            #{e.message}
          MSG
        end

        def classify_sqlite_failure(error)
          message = error.message.to_s.downcase
          return :corrupt_data if message.include?('database disk image is malformed') || message.include?('malformed')
          return :invalid_data if message.include?('file is not a database') || message.include?('no such table')
          return :permission_denied if message.include?('permission denied')

          :internal
        end

        def simple_search(db, word, partial:, limit:)
          query = build_search_query('translation_grouped',
                                     'written_rep, sense_list, trans_list, score, importance',
                                     partial: partial)
          search_term = partial ? "%#{escape_like(word)}%" : word
          params = partial ? [search_term, limit] : [search_term]

          db.execute(query, params)
        end

        def grouped_search(db, word, partial:, limit:)
          query = build_search_query('translation_grouped', '*', partial: partial)
          search_term = partial ? "%#{escape_like(word)}%" : word
          params = partial ? [search_term, limit] : [search_term]

          db.execute(query, params)
        end

        def detailed_search(db, word, partial:, limit:)
          query = build_search_query('translation', '*', partial: partial)
          search_term = partial ? "%#{escape_like(word)}%" : word
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
          match_clause = partial ? "LIKE ? ESCAPE '\\'" : '= ? COLLATE NOCASE'
          limit_clause = partial ? 'LIMIT ?' : ''

          <<~SQL
            SELECT #{columns}
            FROM #{table}
            WHERE written_rep #{match_clause}
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
              AND lower(written_rep) LIKE ? ESCAPE '\\'
              ORDER BY ABS(length(written_rep) - ?) ASC,
                       rel_importance DESC,
                       max_score DESC,
                       lower(written_rep) ASC
              LIMIT ?
            SQL
            params: [min_len, max_len, "#{escape_like(prefix)}%", word_length, candidate_limit],
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
              WHERE lower(trans_list) LIKE ? ESCAPE '\\'
              ORDER BY importance DESC, score DESC, lower(written_rep) ASC
              LIMIT ?
            SQL
            params: ["%#{escape_like(fragment)}%", candidate_limit],
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
          case_clause = "CASE WHEN lower(#{field}) LIKE ? ESCAPE '\\' THEN 1 ELSE 0 END"
          where_clause = "lower(#{field}) LIKE ? ESCAPE '\\'"
          patterns = grams.map { |gram| "%#{escape_like(gram)}%" }

          [
            Array.new(grams.length, case_clause).join(' + '),
            Array.new(grams.length, where_clause).join(' OR '),
            patterns,
          ]
        end

        def fetch_fuzzy_candidates(db, word, limit:)
          lower_word = word.downcase
          min_len, max_len = fuzzy_length_bounds(word)
          candidate_limit = fuzzy_candidate_limit(limit)
          queries = fuzzy_candidate_queries(lower_word,
                                            min_len: min_len,
                                            max_len: max_len,
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
          normalized = FuzzyRanker.normalize_candidate_row(row)
          importance = normalized[:rel_importance] || normalized[:importance]
          score = normalized[:max_score] || normalized[:score]

          tokenize_translation_list(normalized[:trans_list]).filter_map do |token|
            next unless token.length.between?(min_len, max_len)
            next unless translation_candidate_relevant?(word, token)

            { written_rep: token, rel_importance: importance, max_score: score }
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
          normalized_word = FuzzyRanker.normalize_for_comparison(word)
          normalized_token = FuzzyRanker.normalize_for_comparison(token)
          return false if normalized_word.empty? || normalized_token.empty?

          return true if normalized_token.start_with?(normalized_word[0, 2].to_s)
          return true if fuzzy_query_grams(normalized_word).any? { |gram| normalized_token.include?(gram) }

          FuzzyRanker.ngram_similarity(normalized_word, normalized_token, 2) >= 0.35
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
