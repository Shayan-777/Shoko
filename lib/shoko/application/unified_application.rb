# frozen_string_literal: true

require_relative 'cli_progress_presenter'

module Shoko
  module Application
    # Unified application entry point that handles both file and menu scenarios
    class UnifiedApplication
      Dependencies = Data.define(
        :app_mode_runner,
        :terminal_session,
        :instrumentation_service,
        :cache_availability,
        :document_service_factory,
        :cli_progress_renderer,
        :page_calculator,
        :config_reader,
        :state_writer,
        :reader_state_reader,
        :reader_session_context,
        :instrumentation,
        :logger
      )

      def initialize(epub_path = nil, deps:)
        raise ArgumentError, 'UnifiedApplication dependencies are required' if deps.nil?

        @epub_path = epub_path
        @deps = deps
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
        terminal_session = deps.terminal_session
        instrumentation = deps.instrumentation_service

        instrumentation&.start_trace(@epub_path)
        preload_document_if_needed

        # For cold opens, preload/cache in CLI with progress before switching screens.
        # Warm opens still enter the alternate screen immediately for instant-open UX.
        terminal_session.setup
        begin
          deps.app_mode_runner.run_reader(path: @epub_path)
        ensure
          terminal_session.cleanup
          instrumentation&.cancel_trace
        end
      end

      def menu_mode
        deps.app_mode_runner.run_menu
      end

      def preload_document_if_needed
        return unless @epub_path

        cache_availability = deps.cache_availability
        return unless cache_availability
        return if cache_availability.cache_available?(@epub_path)

        factory = deps.document_service_factory
        return unless factory

        presenter = CLIProgressPresenter.new(renderer: deps.cli_progress_renderer)
        presenter.start(message: 'Preparing book...')

        reporter = lambda do |message: nil, progress: nil|
          presenter.update_status(message: message, progress: progress)
        end

        document = factory.call(@epub_path, progress_reporter: reporter).load_document
        session_context = deps.reader_session_context
        session_context.document = document if session_context && document
        build_cli_pagination(document, presenter)
      ensure
        presenter&.finish
      end

      def build_cli_pagination(document, presenter)
        return unless document
        return if document.respond_to?(:cached?) && document.cached?

        page_calculator = deps.page_calculator
        config_reader = deps.config_reader
        state_writer = deps.state_writer
        reader_state_reader = deps.reader_state_reader
        terminal_session = deps.terminal_session
        instrumentation = deps.instrumentation
        return unless page_calculator && config_reader && state_writer

        height, width = terminal_session.size
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
            payload = page_calculator.build_dynamic_map!(width, height, document,
                                                         config_reader: config_reader,
                                                         sidebar_visible: sidebar_visible, &progress)
            state_writer.update_pagination_state(
              total_pages: payload[:total_pages],
              last_width: payload[:last_width],
              last_height: payload[:last_height]
            )
            if reader_state_reader
              restore = page_calculator.apply_pending_precise_restore!(reader_state_reader)
              if restore
                index = restore[:current_page_index]
                state_writer.update_page(current_page_index: index) if index
                state_writer.update_selections(pending_progress: nil) if restore[:clear_pending_progress]
              end
            end
          else
            payload = page_calculator.build_absolute_map!(width, height, document,
                                                          config_reader: config_reader, &progress)
            state_writer.update_pagination_state(payload)
          end
        end

        if instrumentation.respond_to?(:measure)
          instrumentation.measure('pagination.build') { runner.call }
        else
          runner.call
        end

        presenter.update_status(progress: 1.0)
      rescue StandardError => e
        deps.logger&.error('CLI pagination prebuild failed', error: e.message)
      end

      attr_reader :deps
    end
  end
end
