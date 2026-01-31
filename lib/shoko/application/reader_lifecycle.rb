# frozen_string_literal: true

module Shoko
  module Application
    # Manages reader startup and shutdown concerns (terminal setup, background worker).
    class ReaderLifecycle
      def initialize(controller, terminal_service:,
                     background_worker: nil, background_worker_factory: nil,
                     async_executor: nil, instrumentation_service: nil,
                     pagination_cache_preloader: nil)
        @controller = controller
        @terminal_service = terminal_service
        @background_worker = background_worker
        @background_worker_factory = background_worker_factory
        @async_executor = async_executor
        @instrumentation_service = instrumentation_service
        @pagination_cache_preloader = pagination_cache_preloader
      end

      def ensure_background_worker(name: 'reader-background')
        return @background_worker if @background_worker

        factory = @background_worker_factory
        return nil unless factory.respond_to?(:call)

        @background_worker = factory.call(name: name)
        @background_worker
      rescue StandardError
        nil
      end

      attr_reader :background_worker

      def run
        ensure_background_worker
        @terminal_service.setup
        @controller.mark_metrics_start!
        Shoko::Application::ReaderStartupOrchestrator.new(
          terminal_service: @terminal_service,
          async_executor: @async_executor,
          instrumentation_service: @instrumentation_service,
          state_controller: @controller.state_controller,
          pagination_cache_preloader: @pagination_cache_preloader
        ).start(@controller)
        @controller.main_loop
      ensure
        shutdown_background_worker
        @terminal_service.cleanup
      end

      def shutdown_background_worker
        @background_worker&.shutdown
      ensure
        @background_worker = nil
      end
    end
  end
end
