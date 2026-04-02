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
          # @param reader_runtime_context [Core::Ports::Outbound::ReaderRuntimeContext]
          #   Runtime context for terminal size
          # @param pagination_cache [Object, nil] Pagination cache storage
          # @param instrumentation [Core::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          def initialize(reader_runtime_context:, instrumentation:, pagination_cache: nil,
                         logger: nil)
            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @instrumentation = instrumentation
            @logger = logger
          end

          # Bind document and store dependencies into a reusable runtime handle.
          def bind(doc:, page_calculator:, app_config_store:, reader_session_store:,
                   reader_view_state_store:, reader_pagination_store:)
            return nil unless doc && page_calculator

            PaginationRuntime.new(
              session_factory: PaginationSessionFactory.new(
                reader_runtime_context: @reader_runtime_context,
                pagination_cache: @pagination_cache,
                instrumentation: @instrumentation,
                logger: @logger
              ),
              doc: doc,
              page_calculator: page_calculator,
              app_config_store: app_config_store,
              reader_session_store: reader_session_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store
            )
          end
        end
      end
    end
  end
end
