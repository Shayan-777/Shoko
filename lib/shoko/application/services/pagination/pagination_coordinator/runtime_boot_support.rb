# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Extracted coordinator bootstrap helpers so the coordinator entrypoint
        # stays focused on runtime pagination flows.
        module PaginationCoordinatorRuntimeBootSupport
          private

          def assign_core_dependencies(doc:, page_calculator:, layout_service:, pagination_cache:,
                                       notification_writer:, logger:, reader_render_requester:,
                                       async_executor:, instrumentation:, app_config_store:)
            @doc = doc
            @page_calculator = page_calculator
            @layout_service = layout_service
            @pagination_cache = pagination_cache
            @notification_writer = notification_writer
            @logger = logger
            @reader_render_requester = reader_render_requester
            @async_executor = async_executor
            @instrumentation = instrumentation
            @app_config_store = app_config_store
          end

          def assign_reader_state_dependencies(reader_session_store:, reader_state_reader:,
                                               reader_view_state_store:, reader_pagination_store:,
                                               reader_runtime_context:)
            @reader_session_store = reader_session_store
            @reader_state_reader = reader_state_reader || reader_session_store
            @reader_view_state_store = reader_view_state_store || @reader_state_reader
            @reader_pagination_store = reader_pagination_store || @reader_state_reader
            @reader_runtime_context = reader_runtime_context
          end

          def bootstrap_pagination_runtime
            @orchestrator = PaginationOrchestrator.new(
              reader_runtime_context: @reader_runtime_context,
              pagination_cache: @pagination_cache,
              instrumentation: @instrumentation,
              logger: @logger
            )
            @pagination_runtime = build_pagination_runtime
            @pending_initial_calculation = true
            @defer_page_map = false
            @page_calculator&.reset_session!
            seed_flags
          end
        end
      end
    end
  end
end
