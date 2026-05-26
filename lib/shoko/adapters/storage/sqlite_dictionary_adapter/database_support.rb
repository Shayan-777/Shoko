# frozen_string_literal: true

require_relative '../../../shared/optional_dependency'

module Shoko
  module Adapters
    module Storage
      class SqliteDictionaryAdapter
        # Database boundary helpers for the SQLite dictionary adapter.
        module DatabaseSupport
          private

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
            if message.include?('database disk image is malformed') || message.include?('malformed')
              return :corrupt_data
            end
            return :invalid_data if message.include?('file is not a database') || message.include?('no such table')
            return :permission_denied if message.include?('permission denied')

            :internal
          end
        end
      end
    end
  end
end
