# frozen_string_literal: true

module Shoko
  module Application
    # Orchestrates reader startup steps: terminal prep, progress restore,
    # pagination preload, and background data loads.
    class ReaderStartupOrchestrator
      def initialize(dependencies)
        @dependencies = dependencies
        @terminal_service = @dependencies.resolve(:terminal_service)
        @async_executor = @dependencies.resolve(:async_executor)
      end

      # Execute startup sequence using the controller as context
      # @param controller [Shoko::ReaderController]
      def start(controller)
        instrumentation = instrumentation_service
        wrap_with_instrumentation(instrumentation, 'startup.reader') do
          state = controller.state
          page_calculator = controller.page_calculator
          doc = controller.doc

          # Query terminal size (FrameCoordinator will update state during rendering)
          height, width = begin
            @terminal_service.size
          rescue StandardError
            [nil, nil]
          end

          # Load progress after terminal is ready
          sc = safe_resolve_state_controller
          sc&.load_progress

          if doc.respond_to?(:cached?) && doc.cached?
            preloader = resolve_pagination_preloader(state, page_calculator)
            result = preloader&.preload(doc, width:, height:)
            controller.clear_defer_page_map! if result && result.status == :hit
          end

          # Perform initial calculations if needed
          controller.perform_initial_calculations_if_needed if controller.pending_initial_calculation?

          # Schedule background page-map build for instant-open path
          controller.schedule_background_page_map_build if controller.defer_page_map?

          # Background load bookmarks and annotations
          submit_background_job(sc) do
            svc = sc || safe_resolve_state_controller
            if svc
              svc.load_bookmarks
              svc.refresh_annotations
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

      def instrumentation_service
        @instrumentation_service ||= begin
          @dependencies.resolve(:instrumentation_service)
        rescue StandardError
          nil
        end
      end

      def safe_resolve_state_controller
        @dependencies.resolve(:state_controller)
      rescue StandardError
        nil
      end

      def submit_background_job(_initial_state_controller, &)
        resolve_async_executor.submit(&)
      rescue StandardError
        # ignore background failures
        nil
      end

      def resolve_async_executor
        @async_executor
      end

      def resolve_pagination_preloader(_state, _page_calculator)
        return nil unless @dependencies.respond_to?(:resolve)

        @dependencies.resolve(:pagination_cache_preloader)
      rescue StandardError
        nil
      end
    end
  end
end
