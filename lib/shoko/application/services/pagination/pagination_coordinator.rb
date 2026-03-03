# frozen_string_literal: true

require_relative 'page_info_calculator'
require_relative 'pagination_orchestrator'
require_relative '../../../core/ports/outbound/config_reader'

require_relative '../../../core/ports/outbound/reader_navigation_reader'

require_relative '../../../core/ports/outbound/pagination_state_writer'
require_relative '../../../core/ports/outbound/ui_loading_writer'
require_relative '../../../core/ports/outbound/sidebar_state_reader'
require_relative '../../../core/ports/outbound/reader_render_requester'


module Shoko
  module Application
    module Services
      module Pagination
        # Coordinates pagination-related workflows for the reader.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - Reader state reading goes through ReaderNavigationReader port
        # - Pagination writes go through PaginationStateWriter port
        # - Loading overlay writes go through UiLoadingWriter port
        # - All dependencies must be injected (no fallback instantiation)
        # Uses hexagonal ports for reading state - no direct state_store access.
        class PaginationCoordinator
          # @param doc [Object] Document object
          # @param page_calculator [Object] Page calculator service
          # @param layout_service [Object] Layout service
          # @param ui_state_reader [Core::Ports::Outbound::UiStateReader] UI state reader
          # @param pagination_cache [Object] Pagination cache storage
          # @param reader_render_requester [Core::Ports::Outbound::ReaderRenderRequester] Render request boundary
          # @param async_executor [Core::Ports::Outbound::AsyncExecutor] Background executor (required)
          # @param display_capabilities [Core::Ports::Outbound::DisplayCapabilities] Display capability adapter (required)
          # @param instrumentation [Core::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          # @param config_reader [Core::Ports::Outbound::ConfigReader] Port for reading config
          # @param reader_state_reader [Core::Ports::Outbound::ReaderNavigationReader] Port for reading reader state
          # @param pagination_state_writer [Core::Ports::Outbound::PaginationStateWriter] Port for pagination writes
          # @param ui_loading_writer [Core::Ports::Outbound::UiLoadingWriter] Port for loading overlay writes
          # @param sidebar_state_reader [Core::Ports::Outbound::SidebarStateReader] Port for sidebar visibility reads
          # @param notification_writer [Core::Ports::Outbound::NotificationWriter, nil] Port for user-facing messages
          def initialize(doc:, page_calculator:, layout_service:, ui_state_reader:,
                         pagination_cache:, reader_render_requester:,
                         async_executor:, display_capabilities:, instrumentation:,
                         config_reader:, reader_state_reader:, pagination_state_writer:,
                         ui_loading_writer:, sidebar_state_reader:,
                         notification_writer: nil, logger: nil)
            unless reader_render_requester.is_a?(Shoko::Core::Ports::Outbound::ReaderRenderRequester)
              raise ArgumentError, 'reader_render_requester must implement Core::Ports::Outbound::ReaderRenderRequester'
            end

            @doc = doc
            @page_calculator = page_calculator
            @layout_service = layout_service
            @ui_state_reader = ui_state_reader
            @pagination_cache = pagination_cache
            @notification_writer = notification_writer
            @logger = logger
            @reader_render_requester = reader_render_requester
            @async_executor = async_executor
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @pagination_state_writer = pagination_state_writer
            @ui_loading_writer = ui_loading_writer
            @sidebar_state_reader = sidebar_state_reader

            @orchestrator = PaginationOrchestrator.new(
              ui_state_reader: ui_state_reader,
              pagination_cache: pagination_cache,
              display_capabilities: @display_capabilities,
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
            return :pass unless @config_reader.page_numbering_mode == :dynamic

            session(dimensions: terminal_dimensions)&.sync_sidebar_layout(sidebar_visible: sidebar_visible)
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.sync_sidebar_layout failed: #{e.message}")
            :error
          end

          # Apply pending dynamic progress if a page map already exists.
          def apply_pending_progress_if_ready
            return unless @page_calculator
            return unless @config_reader.page_numbering_mode == :dynamic
            return unless @page_calculator.total_pages.to_i.positive?

            restore = @page_calculator.apply_pending_precise_restore!(@reader_state_reader)
            return unless restore

            index = restore[:current_page_index]
            @pagination_state_writer.update_page(current_page_index: index) if index
            @pagination_state_writer.update_selections(pending_progress: nil) if restore[:clear_pending_progress]
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
              ui_state_reader: @ui_state_reader,
              pagination_orchestrator: @orchestrator,
              defer_page_map: defer_page_map?,
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader,
              pagination_state_writer: @pagination_state_writer,
              ui_loading_writer: @ui_loading_writer,
              sidebar_state_reader: @sidebar_state_reader
            )
            calculator.calculate
          rescue ArgumentError, TypeError => e
            @logger&.debug("pagination.page_info failed: #{e.message}")
            { type: :single, current: 0, total: 0 }
          end

          private

          def terminal_dimensions
            width = @ui_state_reader.terminal_width.to_i
            height = @ui_state_reader.terminal_height.to_i
            width = 80 if width <= 0
            height = 24 if height <= 0
            [width, height]
          end

          def session(dimensions: nil)
            @orchestrator.session(
              doc: @doc,
              page_calculator: @page_calculator,
              dimensions: dimensions,
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader,
              pagination_state_writer: @pagination_state_writer,
              ui_loading_writer: @ui_loading_writer,
              sidebar_state_reader: @sidebar_state_reader
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
            return @page_calculator&.total_pages&.positive? if @config_reader.page_numbering_mode == :dynamic

            @reader_state_reader.total_pages.to_i.positive?
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
        end
      end
    end
  end
end
