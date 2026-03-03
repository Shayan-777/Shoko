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
        FUZZY_CANDIDATE_LIMIT = 500

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
          db_path = database_path_for(source_lang, target_lang)
          return [] unless db_path && File.exist?(db_path)

          with_connection(db_path) do |db|
            case mode
            when :exact
              simple_search(db, word, partial: false, limit: limit)
            when :partial
              simple_search(db, word, partial: true, limit: limit)
            when :grouped
              grouped_search(db, word, partial: false, limit: limit)
            when :detailed
              detailed_search(db, word, partial: false, limit: limit)
            when :fuzzy
              fuzzy_search_internal(db, word, limit: limit)
            else
              simple_search(db, word, partial: false, limit: limit)
            end
          end
        end

        # Perform fuzzy search for similar words
        def fuzzy_search(word, source_lang:, target_lang:, limit: 30)
          db_path = database_path_for(source_lang, target_lang)
          return [] unless db_path && File.exist?(db_path)

          with_connection(db_path) do |db|
            fuzzy_search_internal(db, word, limit: limit)
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
        rescue Shoko::Error
          false
        end

        def self.sqlite3_available?
          Kernel.require('sqlite3')
          true
        rescue LoadError
          spec = Shoko::Shared::OptionalDependency.add_gem_load_path('sqlite3')
          return false unless spec

          begin
            Kernel.require('sqlite3')
            true
          rescue LoadError
            false
          end
        rescue Shoko::Error
          false
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
          candidates = fetch_fuzzy_candidates(db, word)
          scored = score_candidates(word, candidates)
          filter_and_sort_fuzzy(scored, limit)
        end

        def fetch_fuzzy_candidates(db, word)
          first_char = word.downcase[0]
          min_len = [word.length - FUZZY_LENGTH_TOLERANCE, 1].max
          max_len = word.length + FUZZY_LENGTH_TOLERANCE

          query = <<~SQL
            SELECT DISTINCT written_rep
            FROM simple_translation
            WHERE lower(written_rep) LIKE ?
            OR length(written_rep) BETWEEN ? AND ?
            LIMIT ?
          SQL

          db.execute(query, ["#{first_char}%", min_len, max_len, FUZZY_CANDIDATE_LIMIT])
        end

        def score_candidates(word, candidates)
          word_lower = word.downcase
          normalized_word = normalize_for_comparison(word)

          candidates.map do |row|
            candidate = row['written_rep']
            similarity = calculate_similarity(word_lower, normalized_word, candidate)
            { word: candidate, similarity: similarity }
          end
        end

        def calculate_similarity(word_lower, normalized_word, candidate)
          candidate_lower = candidate.downcase
          candidate_normalized = normalize_for_comparison(candidate)

          distance_raw = levenshtein_distance(word_lower, candidate_lower)
          distance_normalized = levenshtein_distance(normalized_word, candidate_normalized)
          best_distance = [distance_raw, distance_normalized].min

          max_len = [word_lower.length, candidate.length].max
          1.0 - (best_distance.to_f / max_len)
        end

        def normalize_for_comparison(word)
          word.unicode_normalize(:nfkd)
              .downcase
              .tr('äöüß', 'aous')
              .tr('éèê', 'eee')
        end

        def filter_and_sort_fuzzy(scored, limit)
          scored
            .select { |r| r[:similarity] > 0.4 }
            .sort_by { |r| [-r[:similarity], r[:word].length, r[:word]] }
            .take(limit)
        end

        def levenshtein_distance(source, target)
          return target.length if source.empty?
          return source.length if target.empty?

          matrix = Array.new(source.length + 1) { Array.new(target.length + 1) }

          (0..source.length).each { |i| matrix[i][0] = i }
          (0..target.length).each { |j| matrix[0][j] = j }

          (1..source.length).each do |i|
            (1..target.length).each do |j|
              cost = source[i - 1] == target[j - 1] ? 0 : 1
              matrix[i][j] = [
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost,
              ].min
            end
          end

          matrix[source.length][target.length]
        end

        def log_error(event, **data)
          @logger&.error(event, **data)
        rescue Shoko::Error
          # Silently ignore
        end

        def require_sqlite3!
          Kernel.require('sqlite3')
        rescue LoadError
          spec = Shoko::Shared::OptionalDependency.add_gem_load_path('sqlite3')
          if spec
            begin
              Kernel.require('sqlite3')
              return
            rescue LoadError
              # Fall through to helpful error message below.
            end
          end

          raise Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError.new(
            code: :unavailable,
            message: <<~MSG
            Dictionary lookup requires the optional gem 'sqlite3'.

            Install:
              gem install sqlite3
            On Void Linux you may also need:
              sudo xbps-install -S sqlite-devel
            MSG
          )
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
