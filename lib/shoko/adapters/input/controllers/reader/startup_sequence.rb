# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Orchestrates reader startup: progress restore, preload, and async warmup tasks.
          class StartupSequence
            def initialize(terminal_session:, async_executor:,
                           instrumentation_service: nil, state_controller: nil,
                           pagination_cache_preloader: nil)
              @terminal_session = terminal_session
              @async_executor = async_executor
              @instrumentation_service = instrumentation_service
              @state_controller = state_controller
              @pagination_cache_preloader = pagination_cache_preloader
            end

            def start(controller)
              wrap_with_instrumentation(@instrumentation_service, 'startup.reader') do
                doc = controller.doc

                height, width = begin
                  @terminal_session.size
                rescue Shoko::Error
                  [nil, nil]
                end

                @state_controller&.load_progress
                controller.pagination_coordinator&.apply_pending_progress_if_ready

                if doc&.cached?
                  result = @pagination_cache_preloader&.preload(doc, width:, height:)
                  controller.clear_defer_page_map! if result && result.status == :hit
                end

                controller.perform_initial_calculations_if_needed if controller.pending_initial_calculation?
                controller.schedule_background_page_map_build if controller.defer_page_map?

                submit_background_job do
                  next unless @state_controller

                  @state_controller.load_bookmarks
                  @state_controller.refresh_annotations
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
            rescue Shoko::Error
              nil
            end
          end
        end
      end
    end
  end
end
