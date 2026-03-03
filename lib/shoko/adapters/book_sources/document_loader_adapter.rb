# frozen_string_literal: true

require_relative '../../core/ports/outbound/document_loader'
require_relative '../../core/ports/outbound/reader_launch_state'
require_relative '../../core/ports/outbound/runtime_config'
require_relative '../../core/ports/outbound/line_wrapper'
require_relative '../../core/ports/outbound/chapter_formatter'
require_relative '../../core/ports/outbound/logging'
require_relative '../../core/ports/outbound/book_cache_pipeline_factory'
require_relative 'document_service'

module Shoko
  module Adapters
    module BookSources
      # Adapter that builds a document service and returns loaded documents.
      class DocumentLoaderAdapter
        include Shoko::Core::Ports::Outbound::DocumentLoader

        def initialize(wrapping_service:, formatting_service:, reader_launch_state:, instrumentation:,
                       runtime_config:, logger:, book_cache_pipeline_factory:)
          unless wrapping_service.is_a?(Shoko::Core::Ports::Outbound::LineWrapper)
            raise ArgumentError, 'wrapping_service must implement Core::Ports::Outbound::LineWrapper'
          end
          unless formatting_service.is_a?(Shoko::Core::Ports::Outbound::ChapterFormatter)
            raise ArgumentError, 'formatting_service must implement Core::Ports::Outbound::ChapterFormatter'
          end
          unless reader_launch_state.is_a?(Shoko::Core::Ports::Outbound::ReaderLaunchState)
            raise ArgumentError, 'reader_launch_state must implement Core::Ports::Outbound::ReaderLaunchState'
          end
          unless runtime_config.is_a?(Shoko::Core::Ports::Outbound::RuntimeConfig)
            raise ArgumentError, 'runtime_config must implement Core::Ports::Outbound::RuntimeConfig'
          end
          unless logger.is_a?(Shoko::Core::Ports::Outbound::Logging)
            raise ArgumentError, 'logger must implement Core::Ports::Outbound::Logging'
          end
          unless book_cache_pipeline_factory.is_a?(Shoko::Core::Ports::Outbound::BookCachePipelineFactory)
            raise ArgumentError, 'book_cache_pipeline_factory must implement Core::Ports::Outbound::BookCachePipelineFactory'
          end

          @wrapping_service = wrapping_service
          @formatting_service = formatting_service
          @reader_launch_state = reader_launch_state
          @instrumentation = instrumentation
          @runtime_config = runtime_config
          @logger = logger
          @book_cache_pipeline_factory = book_cache_pipeline_factory
        end

        def load(path:, progress_reporter: nil, background_worker: nil)
          worker = background_worker || @reader_launch_state.background_worker
          book_cache_pipeline = @book_cache_pipeline_factory.build(
            progress_reporter: progress_reporter,
            runtime_config: @runtime_config,
            logger: @logger
          )

          document_service = Shoko::Adapters::BookSources::DocumentService.new(
            path,
            @wrapping_service,
            formatting_service: @formatting_service,
            background_worker: worker,
            progress_reporter: progress_reporter,
            logger: @logger,
            instrumentation: @instrumentation,
            book_cache_pipeline: book_cache_pipeline
          )
          document_service.load_document
        end
      end
    end
  end
end
