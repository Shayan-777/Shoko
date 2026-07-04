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
                           pagination_cache_preloader: nil, image_cache_warmup: nil,
                           kitty_image_renderer: nil, logger: nil)
              @terminal_session = terminal_session
              @async_executor = async_executor
              @instrumentation_service = instrumentation_service
              @state_controller = state_controller
              @pagination_cache_preloader = pagination_cache_preloader
              @image_cache_warmup = image_cache_warmup
              @kitty_image_renderer = kitty_image_renderer
              @logger = logger
            end

            def start(controller)
              wrap_with_instrumentation(@instrumentation_service, 'startup.reader') do
                doc = controller.doc
                width, height = terminal_dimensions

                restore_reader_state(controller)
                preload_cached_pagination(doc, controller, width: width, height: height)
                warm_initial_runtime_state(controller)
                schedule_background_refresh(doc, controller)
              end
            end

            private

            def terminal_dimensions
              height, width = @terminal_session.size
              [width, height]
            end

            def restore_reader_state(controller)
              @state_controller&.load_progress
              controller.pagination_coordinator&.apply_pending_progress_if_ready
            end

            def preload_cached_pagination(doc, controller, width:, height:)
              return unless doc&.cached?

              result = @pagination_cache_preloader&.preload(doc, width:, height:)
              log_debug('startup.pagination_preload', status: result&.status, key: result&.key,
                                                      width: width, height: height)
              case result&.status
              when :hit then controller.clear_defer_page_map!
              # A stale-size layout keeps the reader instantly readable, but the
              # real-size rebuild must still run (with its repagination ticker).
              when :stale then controller.arm_deferred_page_map!
              end
            end

            def warm_initial_runtime_state(controller)
              @kitty_image_renderer&.reset_virtual_placements! if kitty_images_enabled?(controller)
              controller.perform_initial_calculations_if_needed if controller.pending_initial_calculation?
              log_debug('startup.page_map', defer: controller.defer_page_map?,
                                            pending: controller.pending_initial_calculation?)
              controller.schedule_background_page_map_build if controller.defer_page_map?
            end

            def log_debug(event, **data)
              @logger&.debug(event, **data)
            end

            def schedule_background_refresh(doc, controller)
              schedule_session_data_refresh
              schedule_image_warmup(doc) if kitty_images_enabled?(controller)
            end

            def schedule_session_data_refresh
              submit_background_job do
                next unless @state_controller

                @state_controller.load_bookmarks
                @state_controller.refresh_annotations
              end
            end

            def schedule_image_warmup(doc)
              submit_background_job { @image_cache_warmup&.warm_document(doc) }
            end

            def wrap_with_instrumentation(instrumentation, metric, &)
              if instrumentation
                instrumentation.time(metric, &)
              else
                yield
              end
            end

            def submit_background_job(&)
              @async_executor.submit(&)
            # resilient-boundary
            rescue StandardError => e
              swallow_startup_submit_error(e)
            end

            # Startup warmups (session data refresh, image cache) are
            # opportunistic; a submit refused by a shutting-down worker
            # (WorkerStoppedError is a plain StandardError) must not break
            # reader startup.
            def swallow_startup_submit_error(error)
              @logger&.debug('startup.background_submit_failed',
                             error: error.class.name, message: error.message)
            end

            def kitty_images_enabled?(controller)
              controller&.config_reader&.kitty_images == true
            end
          end
        end
      end
    end
  end
end
