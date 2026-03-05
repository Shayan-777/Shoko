# frozen_string_literal: true

require_relative '../../core/ports/outbound/dictionary_repository'
require_relative 'config_paths'

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
          return [] unless db_path && File.exist?(db_path)

          with_connection(db_path) do |db|
            perform_search(db, word: word, mode: mode, query: query, limit: limit)
          end
        end

        # Perform fuzzy search for similar words
        def fuzzy_search(word, source_lang:, target_lang:, limit: 30)
          query = normalize_query_word(word)
          return [] unless query

          db_path = database_path_for(source_lang, target_lang)
          return [] unless db_path && File.exist?(db_path)

          with_connection(db_path) do |db|
            fuzzy_search_internal(db, query, limit: limit)
          end
        end

        # Get available language pairs by scanning database files
        def available_language_pairs
          return [] unless @databases_path && Dir.exist?(@databases_path)

          Dir.glob(File.join(@databases_path, '*.sqlite3')).filter_map do |path|
            basename = File.basename(path, '.sqlite3')
            parts = basename.split('-')
            next unless parts.length == 2

            { source: parts[0], target: parts[1] }
          end
        end

        # Check if a language pair database exists
        def language_pair_available?(source_lang, target_lang)
          path = database_path_for(source_lang, target_lang)
          path && File.exist?(path)
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

        def fetch_fuzzy_candidates(db, word, limit:)
          lower_word = word.downcase
          tolerance = word.length <= 5 ? FUZZY_SHORT_WORD_TOLERANCE : FUZZY_LENGTH_TOLERANCE
          min_len = [word.length - tolerance, 1].max
          max_len = word.length + tolerance
          candidate_limit = fuzzy_candidate_limit(limit)
          first_prefix = lower_word[0, 1]

          primary = db.execute(
            <<~SQL,
              SELECT DISTINCT written_rep
              FROM simple_translation
              WHERE length(written_rep) BETWEEN ? AND ?
              AND lower(written_rep) LIKE ?
              LIMIT ?
            SQL
            [min_len, max_len, "#{first_prefix}%", candidate_limit]
          )

          return primary if primary.length >= candidate_limit

          secondary = db.execute(
            <<~SQL,
              SELECT DISTINCT written_rep
              FROM simple_translation
              WHERE length(written_rep) BETWEEN ? AND ?
              LIMIT ?
            SQL
            [min_len, max_len, candidate_limit]
          )

          merge_unique_candidates(primary, secondary, candidate_limit)
        end

        def score_candidates(word, candidates, similarity_threshold:)
          word_lower = word.downcase
          normalized_word = normalize_for_comparison(word)

          candidates.filter_map do |row|
            candidate = row['written_rep']
            next if candidate.to_s.empty?

            similarity = calculate_similarity(
              word_lower,
              normalized_word,
              candidate,
              similarity_threshold: similarity_threshold
            )
            next unless similarity

            { word: candidate, similarity: similarity }
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
              .tr('äöüß', 'aous')
              .tr('éèê', 'eee')
        end

        def filter_and_sort_fuzzy(scored, limit, similarity_threshold:)
          scored
            .select { |r| r[:similarity] > similarity_threshold }
            .sort_by { |r| [-r[:similarity], r[:word].length, r[:word]] }
            .take(limit)
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

        def merge_unique_candidates(primary, secondary, limit)
          merged = []
          seen = {}
          (Array(primary) + Array(secondary)).each do |row|
            token = row['written_rep'].to_s
            next if token.empty? || seen[token]

            seen[token] = true
            merged << row
            break if merged.length >= limit
          end
          merged
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
