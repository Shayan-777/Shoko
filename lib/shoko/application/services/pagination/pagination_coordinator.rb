# frozen_string_literal: true

require_relative 'page_info_calculator'
require_relative 'pagination_orchestrator'
require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/reader_runtime_context'
require_relative '../../../core/ports/outbound/reader_render_requester'

module Shoko
  module Application
    module Services
      module Pagination
        # Coordinates pagination-related workflows for the reader.
        #
        # This class follows hexagonal architecture principles:
        # - Config and reader state flow through typed session stores
        # - Runtime sizing flows through ReaderRuntimeContext
        # - All dependencies must be injected (no fallback instantiation)
        class PaginationCoordinator
          # @param doc [Object] Document object
          # @param page_calculator [Object] Page calculator service
          # @param layout_service [Object] Layout service
          # @param pagination_cache [Object] Pagination cache storage
          # @param reader_render_requester [Core::Ports::Outbound::ReaderRenderRequester] Render request boundary
          # @param async_executor [Core::Ports::Outbound::AsyncExecutor] Background executor (required)
          # @param instrumentation [Core::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          # @param app_config_store [Core::Ports::Outbound::AppConfigStore] Config snapshot store
          # @param reader_session_store [Core::Ports::Outbound::ReaderSessionStore] Reader snapshot store
          # @param reader_runtime_context [Core::Ports::Outbound::ReaderRuntimeContext] Live runtime context
          # @param notification_writer [Core::Ports::Outbound::NotificationWriter, nil] Port for user-facing messages
          def initialize(doc:, page_calculator:, layout_service:,
                         pagination_cache:, reader_render_requester:,
                         async_executor:, instrumentation:,
                         app_config_store:, reader_session_store:, reader_runtime_context:,
                         notification_writer: nil, logger: nil)
            unless reader_render_requester.is_a?(Shoko::Core::Ports::Outbound::ReaderRenderRequester)
              raise ArgumentError, 'reader_render_requester must implement Core::Ports::Outbound::ReaderRenderRequester'
            end

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
            @reader_session_store = reader_session_store
            @reader_runtime_context = reader_runtime_context

            @orchestrator = PaginationOrchestrator.new(
              reader_runtime_context: reader_runtime_context,
              pagination_cache: pagination_cache,
              instrumentation: @instrumentation,
              logger: @logger
            )
            @pending_initial_calculation = true
            @defer_page_map = false
            @page_calculator&.reset_session!
            seed_flags
          end

          def pending_initial_calculation?
            @pending_initial_calculation
          end

          def defer_page_map?
            @defer_page_map
          end

          def clear_defer_page_map!
            @defer_page_map = false
          end

          def perform_initial_calculations_if_needed
            perform_initial_calculations_with_progress if pending_initial_calculation? && !preloaded_page_data?
            @pending_initial_calculation = false
          end

          def schedule_background_page_map_build
            return unless defer_page_map?

            submit_background_job { build_page_map_in_background }
          end

          def refresh_after_resize(width:, height:)
            return if defer_page_map?

            session(dimensions: [width, height])&.refresh_after_resize
          end

          def rebuild_after_config_change
            session(dimensions: terminal_dimensions)&.rebuild_after_config_change
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.rebuild_after_config_change failed: #{e.message}")
            nil
          end

          def rebuild_dynamic
            result = session&.rebuild_dynamic
            request_render(reason: 'pagination.rebuild_dynamic')
            result
          end

          def sync_sidebar_layout(sidebar_visible:)
            return :pass if defer_page_map?
            return :pass unless current_config.page_numbering_mode == :dynamic

            session(dimensions: terminal_dimensions)&.sync_sidebar_layout(sidebar_visible: sidebar_visible)
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.sync_sidebar_layout failed: #{e.message}")
            :error
          end

          # Apply pending dynamic progress if a page map already exists.
          def apply_pending_progress_if_ready
            return unless @page_calculator
            return unless current_config.page_numbering_mode == :dynamic
            return unless @page_calculator.total_pages.to_i.positive?

            reader_snapshot = current_reader
            restore = @page_calculator.apply_pending_precise_restore!(reader_snapshot)
            return unless restore

            updates = {}
            updates[:current_page_index] = restore[:current_page_index] if restore[:current_page_index]
            updates[:pending_progress] = nil if restore[:clear_pending_progress]
            @reader_session_store.save(reader_snapshot.with(**updates)) unless updates.empty?
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.apply_pending_progress failed: #{e.message}")
          end

          def rebuild_pagination(_key = nil)
            rebuild_dynamic
          end

          def invalidate_cache
            result = session(dimensions: terminal_dimensions)&.invalidate_cache || :missing
            apply_invalidate_message(result)
            :handled
          end

          def invalidate_pagination_cache(_key = nil)
            invalidate_cache
          end

          def page_info
            calculator = PageInfoCalculator.new(
              doc: @doc,
              page_calculator: @page_calculator,
              layout_service: @layout_service,
              reader_runtime_context: @reader_runtime_context,
              pagination_orchestrator: @orchestrator,
              defer_page_map: defer_page_map?,
              app_config_store: @app_config_store,
              reader_session_store: @reader_session_store
            )
            calculator.calculate
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.page_info failed: #{e.message}")
            { type: :single, current: 0, total: 0 }
          end

          private

          def terminal_dimensions
            size = @reader_runtime_context.terminal_size
            [size.width, size.height]
          end

          def session(dimensions: nil)
            @orchestrator.session(
              doc: @doc,
              page_calculator: @page_calculator,
              dimensions: dimensions,
              app_config_store: @app_config_store,
              reader_session_store: @reader_session_store
            )
          end

          def perform_initial_calculations_with_progress
            return unless @doc

            session = session(dimensions: terminal_dimensions)
            return unless session

            session.initial_build
            request_render(reason: 'pagination.initial_build')
          end

          def build_page_map_in_background
            session(dimensions: terminal_dimensions)&.build_full_map
            @defer_page_map = false
            request_render(reason: 'pagination.background_build')
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.build_page_map_in_background failed: #{e.message}")
            @defer_page_map = false
          end

          def submit_background_job(&)
            @async_executor.submit(&)
          # resilient-boundary
          rescue Shoko::Error
            # ignore background failures
          end

          def preloaded_page_data?
            return @page_calculator&.total_pages&.positive? if current_config.page_numbering_mode == :dynamic

            current_reader.total_pages.to_i.positive?
          end

          def seed_flags
            return unless document_cached?

            @pending_initial_calculation = false
            @defer_page_map = true
            return unless @page_calculator && @page_calculator.total_pages.to_i.positive?

            @defer_page_map = false
          end

          def apply_invalidate_message(result)
            return unless @notification_writer

            message = case result
                      when :deleted then 'Pagination cache cleared'
                      when :missing then 'No pagination cache for this layout'
                      else 'Failed to clear pagination cache'
                      end

            @notification_writer.show_message(message)
          end

          def request_render(reason:)
            return unless @reader_render_requester

            @reader_render_requester.request_render(reason: reason)
          rescue Shoko::Core::Ports::Outbound::ReaderRenderRequester::RenderRequestError => e
            @logger&.debug("pagination.request_render failed: #{e.message}")
            nil
          end

          def document_cached?
            @doc&.cached? == true
          end

          def current_config
            @app_config_store.load
          end

          def current_reader
            @reader_session_store.load
          end
        end
      end
    end
  end
end
