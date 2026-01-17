# frozen_string_literal: true

require_relative '../pagination'
require_relative 'page_info_calculator'
require_relative 'pagination_orchestrator'
require_relative '../../ports/config_reader'
require_relative '../../ports/state_writer'

module Shoko
  module Core
    module Services
      module Pagination
        # Coordinates pagination-related workflows for the reader.
        #
        # This class follows hexagonal architecture principles:
        # - Config reading goes through ConfigReader port
        # - State writing goes through StateWriter port
        class PaginationCoordinator
          # @param state [Object] State store for reading state
          # @param doc [Object] Document object
          # @param page_calculator [Object] Page calculator service
          # @param layout_service [Object] Layout service
          # @param terminal_service [Object] Terminal service
          # @param pagination_cache [Object] Pagination cache storage
          # @param frame_coordinator [Object] Frame coordinator
          # @param ui_controller [Object] UI controller
          # @param render_callback [Proc] Render callback
          # @param background_worker_provider [Proc] Background worker provider
          # @param config_reader [Core::Ports::ConfigReader] Port for reading config
          # @param state_writer [Core::Ports::StateWriter] Port for writing state
          def initialize(state:, doc:, page_calculator:, layout_service:, terminal_service:,
                         pagination_cache:, frame_coordinator:, ui_controller:, render_callback:,
                         background_worker_provider:, config_reader:, state_writer:)
            @state = state
            @doc = doc
            @page_calculator = page_calculator
            @layout_service = layout_service
            @terminal_service = terminal_service
            @pagination_cache = pagination_cache
            @ui_controller = ui_controller
            @render_callback = render_callback
            @background_worker_provider = background_worker_provider
            @config_reader = config_reader
            @state_writer = state_writer

            @orchestrator = PaginationOrchestrator.new(
              terminal_service: terminal_service,
              pagination_cache: pagination_cache,
              frame_coordinator: frame_coordinator
            )
            @pending_initial_calculation = true
            @defer_page_map = false
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
          rescue StandardError
            @defer_page_map = false
          end

          def refresh_after_resize(width:, height:)
            return if defer_page_map?

            session(dimensions: [width, height])&.refresh_after_resize
          end

          def rebuild_after_config_change
            session(dimensions: terminal_dimensions)&.rebuild_after_config_change
          rescue StandardError
            nil
          end

          def rebuild_dynamic
            result = session&.rebuild_dynamic
            @render_callback&.call
            result
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
              state: @state,
              doc: @doc,
              page_calculator: @page_calculator,
              layout_service: @layout_service,
              terminal_service: @terminal_service,
              pagination_orchestrator: @orchestrator,
              defer_page_map: defer_page_map?,
              config_reader: @config_reader,
              state_writer: @state_writer
            )
            calculator.calculate
          rescue StandardError
            { type: :single, current: 0, total: 0 }
          end

          private

          def background_worker
            @background_worker_provider&.call
          end

          def terminal_dimensions
            height, width = @terminal_service.size
            [width, height]
          end

          def session(dimensions: nil)
            @orchestrator.session(
              doc: @doc,
              state: @state,
              page_calculator: @page_calculator,
              dimensions: dimensions,
              config_reader: @config_reader,
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
          rescue StandardError
            @defer_page_map = false
          end

          def submit_background_job(&)
            worker = background_worker
            if worker
              worker.submit(&)
            else
              Thread.new do
                yield
              rescue StandardError
                # ignore background failures
              end
            end
          end

          def preloaded_page_data?
            if @config_reader.page_numbering_mode == :dynamic
              return @page_calculator&.total_pages&.positive?
            end

            @state.get(%i[reader total_pages]).to_i.positive?
          end

          def seed_flags
            return unless @doc.respond_to?(:cached?) && @doc.cached?

            @pending_initial_calculation = false
            @defer_page_map = true
            return unless @page_calculator && @page_calculator.total_pages.to_i.positive?

            @defer_page_map = false
          end

          def apply_invalidate_message(result)
            return unless @ui_controller

            case result
            when :deleted
              @ui_controller.set_message('Pagination cache cleared')
            when :missing
              @ui_controller.set_message('No pagination cache for this layout')
            else
              @ui_controller.set_message('Failed to clear pagination cache')
            end
          end
        end
      end
    end
  end
end
