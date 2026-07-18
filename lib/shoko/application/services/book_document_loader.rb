# frozen_string_literal: true

require_relative '../models/reader_document'
require_relative '../ports/outbound/book_cache_store'
require_relative '../ports/outbound/book_importer_resolver'
require_relative '../ports/outbound/book_resource_warmup'
require_relative '../ports/internal/document_loader'

module Shoko
  module Application
    module Services
      # Application workflow for opening a book from cache or source import.
      class BookDocumentLoader
        include Shoko::Application::Ports::Internal::DocumentLoader

        def initialize(book_cache_store:, book_importer_resolver:, runtime_config:, logger: nil,
                       book_resource_warmup: nil)
          validate_contract!(book_cache_store, Shoko::Application::Ports::Outbound::BookCacheStore,
                             'book_cache_store must implement BookCacheStore')
          validate_contract!(book_importer_resolver, Shoko::Application::Ports::Outbound::BookImporterResolver,
                             'book_importer_resolver must implement BookImporterResolver')
          if book_resource_warmup
            validate_contract!(book_resource_warmup, Shoko::Application::Ports::Outbound::BookResourceWarmup,
                               'book_resource_warmup must implement BookResourceWarmup')
          end

          @book_cache_store = book_cache_store
          @book_importer_resolver = book_importer_resolver
          @runtime_config = runtime_config
          @logger = logger
          @book_resource_warmup = book_resource_warmup
        end

        def load(path:, progress_reporter: nil)
          report(progress_reporter, 'Checking cache...')
          cached = @book_cache_store.fetch(path, strict: true)
          return document_for(cached) if cached

          import_and_cache(path, progress_reporter: progress_reporter)
        rescue StandardError => e
          # Type-preserving translation boundary: typed Shoko errors pass
          # through unchanged; anything else (raw third-party leaks like
          # Zip / REXML / JSON parse failures that an importer adapter
          # missed) gets translated to the application's typed
          # BookParseError so callers always see a Shoko::Error.
          raise if e.is_a?(Shoko::Error)

          raise Shoko::BookParseError.new(e.message, path)
        end

        private

        def import_and_cache(path, progress_reporter:)
          report(progress_reporter, 'Importing book...', progress: 0.05)
          book_data = @book_importer_resolver.import(
            path,
            progress_reporter: progress_reporter,
            runtime_config: @runtime_config
          )

          report(progress_reporter, 'Creating JSON cache...', progress: 0.9)
          entry = @book_cache_store.write(path, book_data)
          warm_resources(entry, progress_reporter)
          report(progress_reporter, 'Finalizing cache...', progress: 1.0)
          document_for(entry)
        end

        def document_for(entry)
          Shoko::Application::Models::ReaderDocument.new(
            book: entry.book,
            source_path: entry.source_path,
            cache_path: entry.cache_path,
            cache_sha: entry.source_sha,
            loaded_from_cache: entry.loaded_from_cache
          )
        end

        def warm_resources(entry, progress_reporter)
          return unless @book_resource_warmup

          @book_resource_warmup.warm_book_data(
            book_data: entry.book,
            book_sha: entry.source_sha,
            epub_path: entry.source_path,
            progress_reporter: progress_reporter
          )
        rescue Shoko::Error => e
          @logger&.debug('book_document_loader.resource_warmup_failed', error: e.class.name, message: e.message)
        end

        def report(progress_reporter, message, progress: nil)
          return unless progress_reporter

          progress_reporter.update_status(message: message, progress: progress)
        end

        def validate_contract!(object, contract, message)
          return if object.is_a?(contract)

          raise ArgumentError, message
        end
      end
    end
  end
end
