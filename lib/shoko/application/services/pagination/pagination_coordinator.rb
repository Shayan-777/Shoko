# frozen_string_literal: true

require_relative 'page_info_calculator'
require_relative 'pagination_orchestrator'
require_relative '../../../core/ports/outbound/config_reader'

require_relative '../../../core/ports/outbound/reader_navigation_reader'

require_relative '../../../core/ports/outbound/pagination_state_writer'


module Shoko
  module Application
    module Services
      module Pagination
        # Coordinates pagination-related workflows for the reader.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - Reader state reading goes through ReaderNavigationReader port
        # - State writing goes through PaginationStateWriter port
        # - All dependencies must be injected (no fallback instantiation)
        # Uses hexagonal ports for reading state - no direct state_store access.
        class PaginationCoordinator
          # @param doc [Object] Document object
          # @param page_calculator [Object] Page calculator service
          # @param layout_service [Object] Layout service
          # @param terminal_service [Object] Terminal service
          # @param pagination_cache [Object] Pagination cache storage
          # @param render_callback [Proc] Render callback
          # @param async_executor [Core::Ports::Outbound::AsyncExecutor] Background executor (required)
          # @param display_capabilities [Core::Ports::Outbound::DisplayCapabilities] Display capability adapter (required)
          # @param instrumentation [Core::Ports::Outbound::Instrumentation] Instrumentation adapter (required)
          # @param config_reader [Core::Ports::Outbound::ConfigReader] Port for reading config
          # @param reader_state_reader [Core::Ports::Outbound::ReaderNavigationReader] Port for reading reader state
          # @param state_writer [Core::Ports::Outbound::PaginationStateWriter] Port for pagination state writes
          # @param notification_writer [Core::Ports::Outbound::NotificationWriter, nil] Port for user-facing messages
          def initialize(doc:, page_calculator:, layout_service:, terminal_service:,
                         pagination_cache:, render_callback:,
                         async_executor:, display_capabilities:, instrumentation:,
                         config_reader:, reader_state_reader:, state_writer:,
                         notification_writer: nil, logger: nil)
            @doc = doc
            @page_calculator = page_calculator
            @layout_service = layout_service
            @terminal_service = terminal_service
            @pagination_cache = pagination_cache
            @notification_writer = notification_writer
            @logger = logger
            @render_callback = render_callback
            @async_executor = async_executor
            @display_capabilities = display_capabilities
            @instrumentation = instrumentation
            @config_reader = config_reader
            @reader_state_reader = reader_state_reader
            @state_writer = state_writer

            @orchestrator = PaginationOrchestrator.new(
              terminal_service: terminal_service,
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
          rescue StandardError => e
            @logger&.debug("pagination.schedule_background_build failed: #{e.message}")
            @defer_page_map = false
          end

          def refresh_after_resize(width:, height:)
            return if defer_page_map?

            session(dimensions: [width, height])&.refresh_after_resize
          end

          def rebuild_after_config_change
            session(dimensions: terminal_dimensions)&.rebuild_after_config_change
          rescue StandardError => e
            @logger&.debug("pagination.rebuild_after_config_change failed: #{e.message}")
            nil
          end

          def rebuild_dynamic
            result = session&.rebuild_dynamic
            @render_callback&.call
            result
          end

          def sync_sidebar_layout(sidebar_visible:)
            return :pass if defer_page_map?
            return :pass unless @config_reader.page_numbering_mode == :dynamic

            session(dimensions: terminal_dimensions)&.sync_sidebar_layout(sidebar_visible: sidebar_visible)
          rescue StandardError => e
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
            @state_writer.update_page(current_page_index: index) if index
            @state_writer.update_selections(pending_progress: nil) if restore[:clear_pending_progress]
          rescue StandardError => e
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
              terminal_service: @terminal_service,
              pagination_orchestrator: @orchestrator,
              defer_page_map: defer_page_map?,
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader,
              state_writer: @state_writer
            )
            calculator.calculate
          rescue StandardError => e
            @logger&.debug("pagination.page_info failed: #{e.message}")
            { type: :single, current: 0, total: 0 }
          end

          private

          def terminal_dimensions
            height, width = @terminal_service.size
            [width, height]
          end

          def session(dimensions: nil)
            @orchestrator.session(
              doc: @doc,
              page_calculator: @page_calculator,
              dimensions: dimensions,
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader,
              state_writer: @state_writer
            )
          end

          def perform_initial_calculations_with_progress
            return unless @doc

            session = session(dimensions: terminal_dimensions)
            return unless session

            session.initial_build
            @render_callback&.call
          end

          def build_page_map_in_background
            session(dimensions: terminal_dimensions)&.build_full_map
            @defer_page_map = false
            @render_callback&.call
          rescue StandardError => e
            @logger&.debug("pagination.build_page_map_in_background failed: #{e.message}")
            @defer_page_map = false
          end

          def submit_background_job(&)
            @async_executor.submit(&)
          rescue StandardError
            # ignore background failures
          end

          def preloaded_page_data?
            return @page_calculator&.total_pages&.positive? if @config_reader.page_numbering_mode == :dynamic

            @reader_state_reader.total_pages.to_i.positive?
          end

          def seed_flags
            return unless @doc.respond_to?(:cached?) && @doc.cached?

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
        end
      end
    end
  end
end
