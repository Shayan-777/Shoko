# frozen_string_literal: true

require_relative 'startup_sequence'
require 'shoko/application/ports/outbound/async_executor'
require 'shoko/application/ports/outbound/background_worker_builder'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Manages reader runtime startup/shutdown and background worker lifecycle.
          class LifecycleRunner
            def initialize(controller, terminal_session:,
                           background_worker: nil, background_worker_builder: nil,
                           async_executor: nil, instrumentation_service: nil,
                           logger: nil, pagination_cache_preloader: nil, image_cache_warmup: nil,
                           kitty_image_renderer: nil)
              @controller = controller
              @terminal_session = terminal_session
              @background_worker = background_worker
              @background_worker_builder = background_worker_builder
              @async_executor = async_executor
              @instrumentation_service = instrumentation_service
              @logger = logger
              @pagination_cache_preloader = pagination_cache_preloader
              @image_cache_warmup = image_cache_warmup
              @kitty_image_renderer = kitty_image_renderer
            end

            attr_reader :background_worker

            def ensure_background_worker(name: 'reader-background')
              return @background_worker if @background_worker

              if worker_executor?(@async_executor)
                @background_worker = @async_executor
                return @background_worker
              end

              builder = @background_worker_builder
              unless builder.is_a?(Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder)
                raise Shoko::ConfigurationError, 'background_worker_builder is required and must implement Application::Ports::Outbound::BackgroundWorkerBuilder'
              end

              @background_worker = builder.build(logger: @logger, name: name)
              @async_executor = @background_worker if @async_executor&.synchronous?
              @background_worker
            end

            def run
              ensure_background_worker
              @terminal_session.setup
              @controller.mark_metrics_start!
              startup_sequence.start(@controller)
              @controller.main_loop
            rescue Shoko::FatalExternalInputError => e
              log_fatal_external_input(e)
              @controller.process_control&.terminate(2)
            ensure
              cleanup_session_observers
              shutdown_background_worker
              @terminal_session.cleanup
            end

            def cleanup_session_observers
              @controller.cleanup_observers
            end

            def startup_sequence
              StartupSequence.new(
                terminal_session: @terminal_session,
                async_executor: @async_executor,
                instrumentation_service: @instrumentation_service,
                state_controller: @controller.state_controller,
                pagination_cache_preloader: @pagination_cache_preloader,
                image_cache_warmup: @image_cache_warmup,
                kitty_image_renderer: @kitty_image_renderer,
                logger: @controller.logger
              )
            end

            def shutdown_background_worker
              @background_worker&.shutdown
            ensure
              @background_worker = nil
            end

            def worker_executor?(executor)
              return false unless executor

              executor.is_a?(Shoko::Application::Ports::Outbound::AsyncExecutor) && !executor.synchronous?
            end

            def log_fatal_external_input(error)
              @controller.logger&.error(Shoko::FatalExternalInputError.event_id(error),
                                        error: error.class.name, message: error.message)
            end
          end
        end
      end
    end
  end
end
