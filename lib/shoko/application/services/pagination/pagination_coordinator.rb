# frozen_string_literal: true

require_relative 'page_info_calculator'
require_relative 'pagination_orchestrator'
require_relative '../../../core/services/progress_helper'
require_relative '../../../application/ports/outbound/app_config_store'
require_relative '../../../application/ports/outbound/reader_session_store'
require_relative '../../../application/ports/outbound/reader_runtime_context'
require_relative '../../../application/ports/outbound/reader_render_requester'

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

          # Snapshot of background-pagination feedback. Swapped atomically (a
          # single frozen value per write) so the render thread and the worker
          # thread never see a torn read and we avoid writing to the shared state
          # store off the main thread (whose snapshot writes would clobber
          # concurrent reader-view edits). The render side owns the grace-period
          # timing that suppresses a spinner flash on fast rebuilds.
          RecalcStatus = Data.define(:active, :message, :progress)
          IDLE_RECALC = RecalcStatus.new(active: false, message: nil, progress: nil).freeze

          # @param doc [Object] Document object
          # @param page_calculator [Object] Page calculator service
          # @param layout_service [Object] Layout service
          # @param pagination_cache [Object] Pagination cache storage
          # @param reader_render_requester [Application::Ports::Outbound::ReaderRenderRequester] Render request boundary
          # @param async_executor [Application::Ports::Outbound::AsyncExecutor] Background executor (required)
          # @param instrumentation [Application::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          # @param app_config_store [Application::Ports::Outbound::AppConfigStore] Config snapshot store
          # @param reader_session_store [Application::Ports::Outbound::ReaderSessionStore] Reader snapshot store
          # @param reader_runtime_context [Application::Ports::Outbound::ReaderRuntimeContext] Live runtime context
          # @param notification_writer [Application::Ports::Outbound::NotificationWriter, nil] Port for user-facing messages
          def initialize(doc:, page_calculator:, layout_service:,
                         pagination_cache:, reader_render_requester:,
                         async_executor:, instrumentation:,
                         app_config_store:, reader_session_store:, reader_runtime_context:,
                         reader_state_reader: nil, reader_view_state_store: nil, reader_pagination_store: nil,
                         notification_writer: nil, logger: nil)
            unless reader_render_requester.is_a?(Shoko::Application::Ports::Outbound::ReaderRenderRequester)
              raise ArgumentError, 'reader_render_requester must implement Application::Ports::Outbound::ReaderRenderRequester'
            end

            assign_core_dependencies(
              doc: doc,
              page_calculator: page_calculator,
              layout_service: layout_service,
              pagination_cache: pagination_cache,
              notification_writer: notification_writer,
              logger: logger,
              reader_render_requester: reader_render_requester,
              async_executor: async_executor,
              instrumentation: instrumentation,
              app_config_store: app_config_store
            )
            assign_reader_state_dependencies(
              reader_session_store: reader_session_store,
              reader_state_reader: reader_state_reader,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store,
              reader_runtime_context: reader_runtime_context
            )
            bootstrap_pagination_runtime
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

          # Current background-pagination feedback snapshot (never nil).
          def recalc_status
            @recalc_status || IDLE_RECALC
          end

          # True while a background page-map build (open at a new size, or a live
          # resize) is in flight. Drives the reader's status-bar spinner and the
          # event loop's keep-alive redraws.
          def recalculating?
            recalc_status.active
          end

          def perform_initial_calculations_if_needed
            perform_initial_calculations_with_progress if pending_initial_calculation? && !preloaded_page_data?
            @pending_initial_calculation = false
          end

          def schedule_background_page_map_build
            return unless defer_page_map?

            # Set the feedback flag synchronously on the caller (main) thread so
            # the event loop sees it on its very next iteration and starts polling
            # — otherwise it could block on input before the worker thread runs.
            begin_recalc_feedback('Repaginating…')
            submit_background_job { build_page_map_in_background }
          end

          # Repaginate after a terminal resize on the background worker (single
          # flight + coalescing), so the heavy rebuild no longer blocks the render
          # frame and the status-bar spinner can animate while it runs. Rapid
          # resizes collapse to the latest pending size.
          # Returns true only when this call actually started a new background
          # rebuild (vs. coalescing into one already in flight), so the caller can
          # invalidate width-keyed caches once per resize burst rather than every
          # frame while the rebuild runs.
          def refresh_after_resize(width:, height:)
            return false if defer_page_map?

            start_job = false
            @resize_mutex.synchronize do
              @pending_resize = [width, height]
              unless @resize_in_flight
                @resize_in_flight = true
                start_job = true
              end
            end
            return false unless start_job

            begin_recalc_feedback('Adjusting to new size…')
            submit_background_job { run_pending_resizes }
            true
          end

          def rebuild_after_config_change
            @pagination_runtime&.rebuild_after_config_change(dimensions: terminal_dimensions)
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.rebuild_after_config_change failed: #{e.message}")
            nil
          end

          def rebuild_dynamic
            result = @pagination_runtime&.rebuild_dynamic
            request_render(reason: 'pagination.rebuild_dynamic')
            result
          end

          def sync_sidebar_layout(sidebar_visible:)
            return :pass if defer_page_map?
            return :pass unless current_config.page_numbering_mode == :dynamic

            @pagination_runtime&.sync_sidebar_layout(dimensions: terminal_dimensions, sidebar_visible: sidebar_visible)
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.sync_sidebar_layout failed: #{e.message}")
            :error
          end

          # Apply pending dynamic progress if a page map already exists.
          def apply_pending_progress_if_ready
            return unless pending_progress_ready?

            reader_snapshot = current_reader
            restore = @page_calculator.apply_pending_precise_restore!(reader_snapshot)
            apply_pending_restore(reader_snapshot, restore)
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.apply_pending_progress failed: #{e.message}")
          end

          def rebuild_pagination(_key = nil)
            rebuild_dynamic
          end

          def invalidate_cache
            result = @pagination_runtime&.invalidate_cache(dimensions: terminal_dimensions) || :missing
            apply_invalidate_message(result)
            :handled
          end

          def invalidate_pagination_cache(_key = nil)
            invalidate_cache
          end

          def page_info
            build_page_info_calculator.calculate
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.page_info failed: #{e.message}")
            { type: :single, current: 0, total: 0 }
          end

          private

          def terminal_dimensions
            size = @reader_runtime_context.terminal_size
            [size.width, size.height]
          end

          def build_page_info_calculator
            PageInfoCalculator.new(
              doc: @doc,
              page_calculator: @page_calculator,
              layout_service: @layout_service,
              reader_runtime_context: @reader_runtime_context,
              pagination_runtime: @pagination_runtime,
              defer_page_map: defer_page_map?,
              app_config_store: @app_config_store,
              reader_session_store: @reader_session_store,
              reader_state_reader: @reader_state_reader,
              reader_view_state_store: @reader_view_state_store,
              reader_pagination_store: @reader_pagination_store
            )
          end

          def build_pagination_runtime
            @orchestrator.bind(
              doc: @doc,
              page_calculator: @page_calculator,
              app_config_store: @app_config_store,
              reader_session_store: @reader_session_store,
              reader_view_state_store: @reader_view_state_store,
              reader_pagination_store: @reader_pagination_store
            )
          end

          def perform_initial_calculations_with_progress
            return unless @doc

            return unless @pagination_runtime

            @pagination_runtime.initial_build(dimensions: terminal_dimensions)
            request_render(reason: 'pagination.initial_build')
          end

          def build_page_map_in_background
            @pagination_runtime&.build_full_map(dimensions: terminal_dimensions, progress: method(:report_recalc_progress))
            @defer_page_map = false
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.build_page_map_in_background failed: #{e.message}")
            @defer_page_map = false
          ensure
            finish_recalc_feedback
            request_render(reason: 'pagination.background_build')
          end

          # Drain coalesced resize requests on the worker thread until none remain,
          # then clear the in-flight flag and feedback atomically.
          def run_pending_resizes
            while (dims = claim_pending_resize)
              width, height = dims
              @pagination_runtime&.refresh_after_resize(width: width, height: height,
                                                        progress: method(:report_recalc_progress))
            end
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.refresh_after_resize failed: #{e.message}")
          ensure
            finish_recalc_feedback
            request_render(reason: 'pagination.resize')
          end

          # Atomically take the next pending resize, or release the in-flight flag
          # when none remain. Done under the lock so a resize arriving concurrently
          # either gets claimed here or starts a fresh job — never lost.
          def claim_pending_resize
            @resize_mutex.synchronize do
              dims = @pending_resize
              @pending_resize = nil
              @resize_in_flight = false unless dims
              dims
            end
          end

          def submit_background_job(&)
            @async_executor.submit(&)
          # resilient-boundary
          rescue Shoko::Error
            # ignore background failures
          end

          # ----- background pagination feedback (thread-safe via atomic swap) -----

          def begin_recalc_feedback(message)
            @recalc_status = RecalcStatus.new(active: true, message: message, progress: 0.0)
          end

          # Called from the worker thread per chapter; keeps the status active so a
          # late callback after a coalesced restart re-arms the spinner.
          def report_recalc_progress(done, total)
            current = recalc_status
            ratio = Shoko::Core::Services::ProgressHelper.ratio(done, total)
            @recalc_status = RecalcStatus.new(
              active: true,
              message: current.active ? current.message : 'Repaginating…',
              progress: ratio
            )
          end

          def finish_recalc_feedback
            @recalc_status = IDLE_RECALC
          end

          def preloaded_page_data?
            return @page_calculator&.total_pages&.positive? if current_config.page_numbering_mode == :dynamic

            @reader_pagination_store.total_pages.to_i.positive?
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
          rescue Shoko::Application::Ports::Outbound::ReaderRenderRequester::RenderRequestError => e
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

          # Pending-progress restore helpers for PaginationCoordinator.
          def pending_progress_ready?
            @page_calculator &&
              current_config.page_numbering_mode == :dynamic &&
              @page_calculator.total_pages.to_i.positive?
          end

          def apply_pending_restore(reader_snapshot, restore)
            return unless restore

            updates = pending_restore_updates(restore)
            @reader_session_store.save(reader_snapshot.with(**updates)) unless updates.empty?
          end

          def pending_restore_updates(restore)
            updates = {}
            index = restore[:current_page_index]
            updates[:current_page_index] = index if restore.key?(:current_page_index) && !index.nil?
            updates[:pending_progress] = nil if restore[:clear_pending_progress]
            updates
          end

          # Extracted coordinator bootstrap helpers so the coordinator entrypoint
          # stays focused on runtime pagination flows.
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
            @recalc_status = IDLE_RECALC
            @resize_mutex = Mutex.new
            @resize_in_flight = false
            @pending_resize = nil
            @page_calculator&.reset_session!
            seed_flags
          end
        end
      end
    end
  end
end
