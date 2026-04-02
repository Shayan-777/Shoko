# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Binds document and store dependencies once, then creates fresh pagination
        # sessions per operation so callers no longer wire ad hoc sessions.
        class PaginationRuntime
          def initialize(pagination_session_class:, doc:, page_calculator:, reader_runtime_context:,
                         pagination_cache:, instrumentation:, app_config_store:, reader_session_store:,
                         reader_view_state_store:, reader_pagination_store:, logger: nil)
            @pagination_session_class = pagination_session_class
            @doc = doc
            @page_calculator = page_calculator
            @reader_runtime_context = reader_runtime_context
            @pagination_cache = pagination_cache
            @instrumentation = instrumentation
            @app_config_store = app_config_store
            @reader_session_store = reader_session_store
            @reader_view_state_store = reader_view_state_store
            @reader_pagination_store = reader_pagination_store
            @logger = logger
          end

          def initial_build(dimensions: nil)
            session(dimensions: dimensions)&.initial_build
          end

          def build_full_map(dimensions: nil, progress: nil, &block)
            session(dimensions: dimensions)&.build_full_map(progress: progress || block)
          end

          def refresh_after_resize(width:, height:)
            session(dimensions: [width, height])&.refresh_after_resize
          end

          def rebuild_after_config_change(dimensions: nil)
            session(dimensions: dimensions)&.rebuild_after_config_change
          end

          def rebuild_dynamic(dimensions: nil)
            session(dimensions: dimensions)&.rebuild_dynamic
          end

          def sync_sidebar_layout(sidebar_visible:, dimensions: nil)
            session(dimensions: dimensions)&.sync_sidebar_layout(sidebar_visible: sidebar_visible)
          end

          def invalidate_cache(dimensions: nil)
            session(dimensions: dimensions)&.invalidate_cache
          end

          def ensure_absolute_page_map(width:, height:)
            session(dimensions: [width, height])&.build_full_map
          end

          private

          def session(dimensions:)
            return nil unless @doc && @page_calculator

            @pagination_session_class.new(
              doc: @doc,
              page_calculator: @page_calculator,
              dimensions: dimensions || terminal_dimensions,
              pagination_cache: @pagination_cache,
              config_snapshot: @app_config_store.load,
              reader_session_snapshot: @reader_session_store.load,
              reader_session_store: @reader_session_store,
              reader_view_state_store: @reader_view_state_store,
              reader_pagination_store: @reader_pagination_store,
              display_capabilities: @reader_runtime_context.display_capabilities,
              instrumentation: @instrumentation,
              logger: @logger
            )
          end

          def terminal_dimensions
            size = @reader_runtime_context.terminal_size
            [size.width, size.height]
          end
        end
      end
    end
  end
end
