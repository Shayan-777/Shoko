# frozen_string_literal: true

require_relative 'cli_progress_presenter'

module Shoko
  module Application
    # Unified application entry point that handles both file and menu scenarios
    class UnifiedApplication
      def initialize(epub_path = nil, log_config: {})
        @epub_path = epub_path
        @container = Shoko::Application::Composition::ContainerFactory.create_default_container(log_config: log_config)
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

        instrumentation&.start_trace(@epub_path)
        preload_document_if_needed

        # For cold opens, preload/cache in CLI with progress before switching screens.
        # Warm opens still enter the alternate screen immediately for instant-open UX.
        terminal_service.setup
        begin
          Composition::ContainerFactory.build_reader_controller(@container, @epub_path).run
        ensure
          terminal_service.cleanup
          instrumentation&.cancel_trace
        end
      end

      def menu_mode
        Composition::ContainerFactory.build_menu_controller(@container).run
      end

      def preload_document_if_needed
        return unless @epub_path

        cache_availability = @container.resolve_optional(:cache_availability)
        return unless cache_availability
        return if cache_availability.cache_available?(@epub_path)

        factory = @container.resolve_optional(:document_service_factory)
        return unless factory

        presenter = CLIProgressPresenter.new(renderer: @container.resolve(:cli_progress_renderer))
        presenter.start(message: 'Preparing book...')

        reporter = lambda do |message: nil, progress: nil|
          presenter.update_status(message: message, progress: progress)
        end

        document = factory.call(@epub_path, progress_reporter: reporter).load_document
        session_context = @container.resolve_optional(:reader_session_context)
        session_context.document = document if session_context && document
        build_cli_pagination(document, presenter)
      ensure
        presenter&.finish
      end

      def build_cli_pagination(document, presenter)
        return unless document
        return if document.respond_to?(:cached?) && document.cached?

        page_calculator = @container.resolve_optional(:page_calculator)
        config_reader = @container.resolve_optional(:config_reader)
        state_writer = @container.resolve_optional(:state_writer)
        reader_state_reader = @container.resolve_optional(:reader_state_reader)
        terminal_service = @container.resolve(:terminal_service)
        instrumentation = @container.resolve_optional(:instrumentation)
        return unless page_calculator && config_reader && state_writer

        height, width = terminal_service.size
        return unless width && height

        presenter.update_status(message: 'Calculating pages...', progress: 0.0)
        progress = lambda do |done, total|
          ratio = Shoko::Core::Services::ProgressHelper.ratio(done, total)
          total_i = total.to_i
          message = if total_i.positive?
                      "Calculating pages (#{done.to_i}/#{total_i})..."
                    else
                      'Calculating pages...'
                    end
          presenter.update_status(message: message, progress: ratio)
        end

        runner = lambda do
          if config_reader.page_numbering_mode == :dynamic
            sidebar_visible = reader_state_reader&.sidebar_visible? == true
            page_calculator.build_dynamic_map!(width, height, document,
                                               state_writer: state_writer,
                                               config_reader: config_reader,
                                               sidebar_visible: sidebar_visible, &progress)
            if reader_state_reader
              page_calculator.apply_pending_precise_restore!(reader_state_reader, state_writer: state_writer)
            end
          else
            page_calculator.build_absolute_map!(width, height, document,
                                                state_writer: state_writer,
                                                config_reader: config_reader, &progress)
          end
        end

        if instrumentation.respond_to?(:measure)
          instrumentation.measure('pagination.build') { runner.call }
        else
          runner.call
        end

        presenter.update_status(progress: 1.0)
      rescue StandardError => e
        @container.resolve_optional(:logger)&.error('CLI pagination prebuild failed', error: e.message)
      end
    end
  end
end
