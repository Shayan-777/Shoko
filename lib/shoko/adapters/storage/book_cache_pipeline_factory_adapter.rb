# frozen_string_literal: true

require_relative '../../core/ports/outbound/book_cache_pipeline_factory'
require_relative 'book_cache_pipeline'

module Shoko
  module Adapters
    module Storage
      # Adapter that constructs BookCachePipeline instances through a typed outbound port.
      class BookCachePipelineFactoryAdapter
        include Shoko::Core::Ports::Outbound::BookCachePipelineFactory

        def initialize(image_cache_warmup: nil)
          @image_cache_warmup = image_cache_warmup
        end

        def build(progress_reporter:, runtime_config:, logger:)
          Shoko::Adapters::Storage::BookCachePipeline.new(
            progress_reporter: progress_reporter,
            runtime_config: runtime_config,
            logger: logger,
            image_cache_warmup: @image_cache_warmup
          )
        end
      end
    end
  end
end
