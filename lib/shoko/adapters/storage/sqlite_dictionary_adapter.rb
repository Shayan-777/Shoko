# frozen_string_literal: true

require_relative '../../core/ports/outbound/dictionary_repository'
require_relative 'config_paths'
require_relative '../../shared/type_coercion'
require_relative 'sqlite_dictionary_adapter/database_support'
require_relative 'sqlite_dictionary_adapter/fuzzy_query_support'
require_relative 'sqlite_dictionary_adapter/fuzzy_ranking_support'

module Shoko
  module Adapters
    module Storage
      # SQLite adapter for dictionary database operations.
      class SqliteDictionaryAdapter
        include Core::Ports::Outbound::DictionaryRepository
        include DatabaseSupport
        include FuzzyQuerySupport
        include FuzzyRankingSupport

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

        private

        def resolve_databases_path(databases_path)
          if databases_path && !databases_path.to_s.strip.empty?
            File.expand_path(databases_path.to_s)
          else
            self.class.default_databases_path
          end
        end
      end
    end
  end
end
