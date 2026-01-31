# frozen_string_literal: true

module Shoko
  module Application
    # Orchestrates reader startup steps: terminal prep, progress restore,
    # pagination preload, and background data loads.
    class ReaderStartupOrchestrator
      def initialize(terminal_service:, async_executor:,
                     instrumentation_service: nil, state_controller: nil,
                     pagination_cache_preloader: nil)
        @terminal_service = terminal_service
        @async_executor = async_executor
        @instrumentation_service = instrumentation_service
        @state_controller = state_controller
        @pagination_cache_preloader = pagination_cache_preloader
      end

      # Execute startup sequence using the controller as context
      # @param controller [Shoko::ReaderController]
      def start(controller)
        wrap_with_instrumentation(@instrumentation_service, 'startup.reader') do
          doc = controller.doc

          # Query terminal size (FrameCoordinator will update state during rendering)
          height, width = begin
            @terminal_service.size
          rescue StandardError
            [nil, nil]
          end

          # Load progress after terminal is ready
          @state_controller&.load_progress

          if doc.respond_to?(:cached?) && doc.cached?
            result = @pagination_cache_preloader&.preload(doc, width:, height:)
            controller.clear_defer_page_map! if result && result.status == :hit
          end

          # Perform initial calculations if needed
          controller.perform_initial_calculations_if_needed if controller.pending_initial_calculation?

          # Schedule background page-map build for instant-open path
          controller.schedule_background_page_map_build if controller.defer_page_map?

          # Background load bookmarks and annotations
          submit_background_job do
            if @state_controller
              @state_controller.load_bookmarks
              @state_controller.refresh_annotations
            end
          end
        end
      end

      private

      def wrap_with_instrumentation(instrumentation, metric, &)
        if instrumentation
          instrumentation.time(metric, &)
        else
          yield
        end
      end

      def submit_background_job(&)
        @async_executor.submit(&)
      rescue StandardError
        # ignore background failures
        nil
      end
    end
  end
end
