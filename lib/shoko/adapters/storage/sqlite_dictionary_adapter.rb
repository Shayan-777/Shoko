# frozen_string_literal: true

require_relative '../../core/ports/outbound/dictionary_repository'
require_relative 'config_paths'
require_relative '../../shared/type_coercion'

module Shoko
  module Adapters
    module Storage
      # SQLite adapter for dictionary database operations.
      # Implements the DictionaryRepository port interface.
      class SqliteDictionaryAdapter
        include Core::Ports::Outbound::DictionaryRepository

        LANGUAGE_CODES = {
          'german' => 'de', 'english' => 'en',
          'russian' => 'ru', 'chinese' => 'zh',
          'de' => 'de', 'en' => 'en', 'ru' => 'ru', 'zh' => 'zh'
        }.freeze

        FUZZY_LENGTH_TOLERANCE = 3
        FUZZY_SHORT_WORD_TOLERANCE = 2
        FUZZY_CANDIDATE_MULTIPLIER = 25
        FUZZY_CANDIDATE_FLOOR = 80
        FUZZY_CANDIDATE_LIMIT = 500
        FUZZY_SIMILARITY_THRESHOLD = 0.4
        FUZZY_PREFIX_LENGTHS = [3, 2, 1].freeze
        SQLITE_HEADER = "SQLite format 3\0"
        TRANSLATION_TOKEN = /\p{L}[\p{L}\p{M}\p{N}'’-]*/.freeze

        def initialize(databases_path: nil, logger: nil)
          @databases_path = if databases_path && !databases_path.to_s.strip.empty?
                              File.expand_path(databases_path.to_s)
                            else
                              default_databases_path
                            end
          @connection_cache = {}
          @logger = logger
        end

        # Search for a word in the dictionary
        def search(word, source_lang:, target_lang:, mode: :exact, limit: 10)
          query = mode == :fuzzy ? normalize_query_word(word) : word
          return [] if mode == :fuzzy && query.nil?

          db_path = database_path_for(source_lang, target_lang)
          return [] unless valid_database_file?(db_path)

          with_connection(db_path) do |db|
            perform_search(db, word: word, mode: mode, query: query, limit: limit)
          end
        end

        # Perform fuzzy search for similar words
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

        # Get available language pairs by scanning database files
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

        # Check if a language pair database exists
        def language_pair_available?(source_lang, target_lang)
          path = database_path_for(source_lang, target_lang)
          valid_database_file?(path)
        end

        # Get database file path for a language pair
        def database_path_for(source_lang, target_lang)
          source_code = normalize_lang_code(source_lang)
          target_code = normalize_lang_code(target_lang)
          return nil unless source_code && target_code

          File.join(@databases_path, "#{source_code}-#{target_code}.sqlite3")
        end

        private

        def default_databases_path
          self.class.default_databases_path
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

        def normalize_lang_code(lang)
          LANGUAGE_CODES[lang&.downcase]
        end

        def with_connection(db_path)
          require_sqlite3!
          # Simple connection management - create new connection each time
          # to avoid threading issues
          db = SQLite3::Database.new(db_path)
          db.results_as_hash = true
          begin
            yield db
          ensure
            db.close
          end
        rescue SQLite3::Exception => e
          log_error('sqlite_dictionary_error', path: db_path, error: e.message)
          raise Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError.new(
            code: classify_sqlite_failure(e),
            message: e.message,
            details: { path: db_path, error_class: e.class.name }
          )
        end

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

        def score_candidates(word, candidates, similarity_threshold:)
          word_lower = word.downcase
          normalized_word = normalize_for_comparison(word)

          candidates.filter_map do |row|
            candidate = row['written_rep']
            next if candidate.to_s.empty?

            candidate_normalized = normalize_for_comparison(candidate)
            edit_similarity = calculate_similarity(
              word_lower,
              normalized_word,
              candidate,
              similarity_threshold: similarity_threshold
            )
            next unless edit_similarity

            importance = numeric_rank_value(row['rel_importance'] || row[:rel_importance] ||
                                            row['importance'] || row[:importance])
            score = numeric_rank_value(row['max_score'] || row[:max_score] ||
                                       row['score'] || row[:score])

            similarity = composite_similarity(
              word: word,
              candidate: candidate,
              normalized_word: normalized_word,
              candidate_normalized: candidate_normalized,
              edit_similarity: edit_similarity,
              importance: importance,
              score: score
            )

            { word: candidate, similarity: similarity, importance: importance, score: score }
          end
        end

        def calculate_similarity(word_lower, normalized_word, candidate, similarity_threshold:)
          candidate_lower = candidate.downcase
          candidate_normalized = normalize_for_comparison(candidate)
          max_len = [word_lower.length, candidate.length].max
          return nil if max_len.zero?

          max_distance = ((1.0 - similarity_threshold) * max_len).floor

          distance_raw = levenshtein_distance(word_lower, candidate_lower, max_distance: max_distance)
          distance_normalized = levenshtein_distance(normalized_word, candidate_normalized, max_distance: max_distance)
          best_distance = [distance_raw, distance_normalized].min
          return nil if best_distance > max_distance

          1.0 - (best_distance.to_f / max_len)
        end

        def normalize_for_comparison(word)
          word.unicode_normalize(:nfkd)
              .downcase
              .gsub(/\p{Mn}+/, '')
              .gsub('ß', 'ss')
        end

        def filter_and_sort_fuzzy(scored, limit, similarity_threshold:)
          scored
            .select { |r| r[:similarity] > similarity_threshold }
            .sort_by { |r| [-r[:similarity], -r[:importance], -r[:score], r[:word].length, r[:word].downcase] }
            .take(limit)
        end

        def fuzzy_candidate_queries(lower_word, min_len:, max_len:, candidate_limit:)
          queries = prefix_candidate_queries(lower_word, min_len: min_len, max_len: max_len, candidate_limit: candidate_limit)
          grams = fuzzy_query_grams(lower_word)
          queries << ngram_candidate_query(lower_word, grams, min_len: min_len, max_len: max_len,
                                           candidate_limit: candidate_limit) unless grams.empty?
          queries << fallback_candidate_query(lower_word, min_len: min_len, max_len: max_len, candidate_limit: candidate_limit)
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

        def composite_similarity(word:, candidate:, normalized_word:, candidate_normalized:, edit_similarity:, importance:, score:)
          bigram = ngram_similarity(normalized_word, candidate_normalized, 2)
          trigram = ngram_similarity(normalized_word, candidate_normalized, 3)
          prefix = shared_edge_ratio(normalized_word, candidate_normalized, :prefix)
          suffix = shared_edge_ratio(normalized_word, candidate_normalized, :suffix)
          importance_bonus = [importance, 1.0].min * 0.08
          score_bonus = [[score / 250.0, 0.0].max, 1.0].min * 0.02
          start_bonus = normalized_word[0] == candidate_normalized[0] ? 0.03 : 0.0
          case_adjustment = case_similarity_adjustment(word, candidate)

          combined = (edit_similarity * 0.60) +
                     (bigram * 0.16) +
                     (trigram * 0.10) +
                     (prefix * 0.06) +
                     (suffix * 0.05) +
                     importance_bonus +
                     score_bonus +
                     start_bonus +
                     case_adjustment

          combined.clamp(0.0, 0.999)
        end

        def ngram_similarity(source, target, size)
          source_grams = grams_for(source, size)
          target_grams = grams_for(target, size)
          return 0.0 if source_grams.empty? || target_grams.empty?

          overlap = source_grams.sum do |gram, count|
            [count, target_grams.fetch(gram, 0)].min
          end
          denominator = source_grams.values.sum + target_grams.values.sum
          return 0.0 if denominator.zero?

          (2.0 * overlap) / denominator
        end

        def grams_for(value, size)
          text = value.to_s
          return {} if text.length < size

          counts = Hash.new(0)
          0.upto(text.length - size) do |index|
            counts[text[index, size]] += 1
          end
          counts
        end

        def shared_edge_ratio(source, target, edge)
          limit = [source.length, target.length].min
          return 0.0 if limit.zero?

          shared = 0
          while shared < limit
            source_index = edge == :suffix ? -1 - shared : shared
            target_index = edge == :suffix ? -1 - shared : shared
            break unless source[source_index] == target[target_index]

            shared += 1
          end

          shared.to_f / [source.length, target.length].max
        end

        def case_similarity_adjustment(word, candidate)
          return 0.0 if word.to_s.empty? || candidate.to_s.empty?

          query = word.to_s
          token = candidate.to_s
          return -0.08 if query == query.downcase && token[0] == token[0].upcase
          return 0.02 if query[0] == query[0].upcase && token[0] == token[0].upcase

          0.0
        end

        def numeric_rank_value(value)
          Shoko::Shared::TypeCoercion.optional_float(value) || 0.0
        end

        def valid_database_file?(path)
          return false if path.to_s.strip.empty?
          return false unless File.file?(path)
          return false unless File.readable?(path)
          return false unless File.size?(path)

          File.binread(path, SQLITE_HEADER.bytesize) == SQLITE_HEADER
        end

        def levenshtein_distance(source, target, max_distance: nil)
          return target.length if source.empty?
          return source.length if target.empty?

          source_len = source.length
          target_len = target.length
          bounded = bounded_length_gap_distance(source_len, target_len, max_distance)
          return bounded if bounded

          compute_levenshtein_distance(
            source,
            target,
            source_len: source_len,
            target_len: target_len,
            max_distance: max_distance
          )
        end

        def bounded_length_gap_distance(source_len, target_len, max_distance)
          return nil unless max_distance

          return max_distance + 1 if (source_len - target_len).abs > max_distance

          nil
        end

        def compute_levenshtein_distance(source, target, source_len:, target_len:, max_distance:)
          previous = (0..target_len).to_a
          current = Array.new(target_len + 1, 0)
          row_state = { target_len: target_len, previous: previous, current: current }

          (1..source_len).each do |i|
            min_in_row = fill_distance_row!(source, target, i, row_state)
            return max_distance + 1 if max_distance && min_in_row > max_distance

            row_state[:previous], row_state[:current] = row_state[:current], row_state[:previous]
          end

          row_state[:previous][target_len]
        end

        def fill_distance_row!(source, target, source_index, row_state)
          target_len = row_state[:target_len]
          previous = row_state[:previous]
          current = row_state[:current]
          current[0] = source_index
          min_in_row = current[0]

          (1..target_len).each do |target_index|
            cost = source[source_index - 1] == target[target_index - 1] ? 0 : 1
            current[target_index] = [
              previous[target_index] + 1,
              current[target_index - 1] + 1,
              previous[target_index - 1] + cost,
            ].min
            min_in_row = [min_in_row, current[target_index]].min
          end

          min_in_row
        end

        def normalize_query_word(word)
          query = word.to_s.strip
          return nil if query.empty?

          query
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
          # Silently ignore
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
      end
    end
  end
end
