# frozen_string_literal: true

require_relative 'startup_sequence'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Manages reader runtime startup/shutdown and background worker lifecycle.
          class LifecycleRunner
            def initialize(controller, terminal_session:,
                           background_worker: nil, background_worker_factory: nil,
                           async_executor: nil, instrumentation_service: nil,
                           logger: nil, pagination_cache_preloader: nil)
              @controller = controller
              @terminal_session = terminal_session
              @background_worker = background_worker
              @background_worker_factory = background_worker_factory
              @async_executor = async_executor
              @instrumentation_service = instrumentation_service
              @logger = logger
              @pagination_cache_preloader = pagination_cache_preloader
            end

            attr_reader :background_worker

            def ensure_background_worker(name: 'reader-background')
              return @background_worker if @background_worker

              if worker_executor?(@async_executor)
                @background_worker = @async_executor
                return @background_worker
              end

              factory = @background_worker_factory
              return nil unless factory.respond_to?(:call)

              @background_worker = factory.call(logger: @logger, name: name)
              @async_executor = @background_worker if inline_executor?(@async_executor)
              @background_worker
            rescue ArgumentError
              @background_worker = factory.call(name: name)
              @async_executor = @background_worker if inline_executor?(@async_executor)
              @background_worker
            rescue StandardError
              nil
            end

            def run
              ensure_background_worker
              @terminal_session.setup
              @controller.mark_metrics_start!
              StartupSequence.new(
                terminal_session: @terminal_session,
                async_executor: @async_executor,
                instrumentation_service: @instrumentation_service,
                state_controller: @controller.state_controller,
                pagination_cache_preloader: @pagination_cache_preloader
              ).start(@controller)
              @controller.main_loop
            ensure
              cleanup_session_observers
              shutdown_background_worker
              @terminal_session.cleanup
            end

            def cleanup_session_observers
              @controller.cleanup_observers
            rescue StandardError
              nil
            end

            def shutdown_background_worker
              @background_worker&.shutdown
            ensure
              @background_worker = nil
            end

            def worker_executor?(executor)
              return false unless executor

              executor.respond_to?(:submit) && executor.respond_to?(:shutdown) && !inline_executor?(executor)
            end

            def inline_executor?(executor)
              return false unless executor
              return false unless defined?(Shoko::Core::Services::InlineExecutor)

              executor.is_a?(Shoko::Core::Services::InlineExecutor)
            end
          end
        end
      end
    end
  end
end
