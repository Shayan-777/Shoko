# frozen_string_literal: true

module Shoko
  module Application
    # Unified application entry point that handles both file and menu scenarios
    class UnifiedApplication
      def initialize(epub_path = nil, log_config: {})
        @epub_path = epub_path
        @container = Shoko::Application::ContainerFactory.create_default_container(log_config: log_config)
      end

      def run
        if @epub_path
          reader_mode
        else
          menu_mode
        end
      end

      private

      def reader_mode
        terminal_service = @container.resolve(:terminal_service)
        instrumentation = @container.resolve_optional(:instrumentation_service)

        # Ensure alternate screen is entered before any heavy work for instant-open UX
        terminal_service.setup
        instrumentation&.start_trace(@epub_path)
        begin
          ContainerFactory.build_reader_controller(@container, @epub_path).run
        ensure
          terminal_service.cleanup
          instrumentation&.cancel_trace
        end
      end

      def menu_mode
        ContainerFactory.build_menu_controller(@container).run
      end
    end
  end
end
