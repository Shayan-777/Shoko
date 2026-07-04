# frozen_string_literal: true

require_relative 'pagination_runtime'
require_relative 'pagination_session_factory'

module Shoko
  module Application
    module Services
      module Pagination
        # Handles pagination builds (dynamic/absolute) and progress overlay.
        # Keeps heavy orchestration out of ReaderController while preserving behavior.
        #
        # This class follows hexagonal architecture principles:
        # - Reader session/pagination/view state flow through focused stores
        # - Config flows through AppConfigStore
        # - Runtime sizing/display flows through ReaderRuntimeContext
        class PaginationOrchestrator
          # @param reader_runtime_context [Application::Ports::Outbound::ReaderRuntimeContext]
          #   Runtime context for terminal size
          # @param pagination_cache [Object, nil] Pagination cache storage
          # @param instrumentation [Application::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          def initialize(reader_runtime_context:, instrumentation:, pagination_cache: nil,
                         logger: nil)
            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @instrumentation = instrumentation
            @logger = logger
          end

          # Bind document and store dependencies into a reusable runtime handle.
          # The document may be late-bound (direct file opens build the reader
          # graph before the document loads); a document_provider stands in
          # for it until it exists.
          def bind(doc:, page_calculator:, app_config_store:, reader_session_store:,
                   reader_view_state_store:, reader_pagination_store:, document_provider: nil)
            return nil unless (doc || document_provider) && page_calculator

            PaginationRuntime.new(
              session_factory: build_session_factory,
              doc: doc,
              document_provider: document_provider,
              page_calculator: page_calculator,
              app_config_store: app_config_store,
              reader_session_store: reader_session_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store
            )
          end

          private

          def build_session_factory
            PaginationSessionFactory.new(
              reader_runtime_context: @reader_runtime_context,
              pagination_cache: @pagination_cache,
              instrumentation: @instrumentation,
              logger: @logger
            )
          end
        end
      end
    end
  end
end
