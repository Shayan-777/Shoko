# frozen_string_literal: true

require_relative '../../application/ports/outbound/folder_importer'
require_relative '../../application/ports/outbound/document_loader'
require_relative '../../application/ports/outbound/document_warmup'
require_relative '../support/progress_range_reporter'

module Shoko
  module Adapters
    module BookSources
      # Imports a document into cache through the existing document service pipeline.
      class CacheImportAdapter
        include Shoko::Application::Ports::Outbound::FolderImporter

        def initialize(document_loader:, document_warmup: nil)
          unless document_loader.is_a?(Shoko::Application::Ports::Outbound::DocumentLoader)
            raise ArgumentError, 'document_loader must implement Application::Ports::Outbound::DocumentLoader'
          end
          if document_warmup && !document_warmup.is_a?(Shoko::Application::Ports::Outbound::DocumentWarmup)
            raise ArgumentError, 'document_warmup must implement Application::Ports::Outbound::DocumentWarmup'
          end

          @document_loader = document_loader
          @document_warmup = document_warmup
        end

        def import(path, progress_reporter: nil)
          document = @document_loader.load(
            path: path,
            progress_reporter: load_progress_reporter(progress_reporter),
            background_worker: nil
          )
          raise Shoko::BookParseError.new('document import returned nil', path) unless document

          warm_document(document, progress_reporter: progress_reporter)
          progress_reporter&.update_status(message: "Imported #{File.basename(path.to_s)}", progress: 1.0)
          document.cached? ? :skipped : :imported
        end

        private

        def warm_document(document, progress_reporter:)
          return unless @document_warmup

          @document_warmup.warm(document, progress_reporter: warmup_progress_reporter(progress_reporter))
        end

        def load_progress_reporter(progress_reporter)
          stage_progress_reporter(progress_reporter, start_progress: 0.0, end_progress: warmup_enabled? ? 0.85 : 1.0)
        end

        def warmup_progress_reporter(progress_reporter)
          stage_progress_reporter(progress_reporter, start_progress: 0.85, end_progress: 1.0)
        end

        def stage_progress_reporter(progress_reporter, start_progress:, end_progress:)
          return nil unless progress_reporter

          Shoko::Adapters::Support::ProgressRangeReporter.new(
            reporter: progress_reporter,
            start_progress: start_progress,
            end_progress: end_progress
          )
        end

        def warmup_enabled?
          !@document_warmup.nil?
        end
      end
    end
  end
end
