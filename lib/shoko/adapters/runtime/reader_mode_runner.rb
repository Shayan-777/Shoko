# frozen_string_literal: true

require_relative 'cli_progress_presenter'
require_relative '../../core/ports/outbound/document_loader'

module Shoko
  module Adapters
    module Runtime
      # Adapter-owned reader startup/runtime orchestration.
      class ReaderModeRunner
        ProgressReporter = Data.define(:presenter) do
          def update_status(message: nil, progress: nil)
            presenter.update_status(message: message, progress: progress)
          end
        end

        def initialize(build_reader_controller:, terminal_session:, instrumentation_service:, cache_availability:,
                       document_loader:, cli_progress_renderer:, page_calculator:, app_config_store:,
                       reader_session_store:, reader_runtime_context:, reader_launch_state:, instrumentation:, logger:)
          @build_reader_controller = build_reader_controller
          @terminal_session = terminal_session
          @instrumentation_service = instrumentation_service
          @cache_availability = cache_availability
          @document_loader = document_loader
          @cli_progress_renderer = cli_progress_renderer
          @page_calculator = page_calculator
          @app_config_store = app_config_store
          @reader_session_store = reader_session_store
          @reader_runtime_context = reader_runtime_context
          @reader_launch_state = reader_launch_state
          @instrumentation = instrumentation
          @logger = logger
        end

        def run(path:)
          @instrumentation_service&.start_trace(path)
          preload_document_if_needed(path)
          @terminal_session.setup
          begin
            @build_reader_controller.call(path).run
          ensure
            @terminal_session.cleanup
            @instrumentation_service&.cancel_trace
          end
        end

        private

        def preload_document_if_needed(path)
          return unless path
          return unless @cache_availability
          return if @cache_availability.cache_available?(path)

          validate_document_loader!

          presenter = Shoko::Adapters::Runtime::CLIProgressPresenter.new(renderer: @cli_progress_renderer)
          presenter.start(message: 'Preparing book...')

          document = @document_loader.load(path: path, progress_reporter: ProgressReporter.new(presenter))
          @reader_launch_state.set_preloaded_document(document) if @reader_launch_state && document
          build_cli_pagination(document, presenter)
        ensure
          presenter&.finish
        end

        def build_cli_pagination(document, presenter)
          return unless document
          return if document.cached?
          return unless @page_calculator && @app_config_store && @reader_session_store && @reader_runtime_context

          config_snapshot = @app_config_store.load
          reader_snapshot = @reader_session_store.load
          terminal_size = @reader_runtime_context.terminal_size
          width = terminal_size.width
          height = terminal_size.height
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
            if config_snapshot.page_numbering_mode == :dynamic
              reader_snapshot = build_dynamic_pagination(
                width: width,
                height: height,
                document: document,
                config_snapshot: config_snapshot,
                reader_snapshot: reader_snapshot,
                progress: progress
              )
            else
              payload = @page_calculator.build_absolute_map!(
                width,
                height,
                document,
                config_reader: config_snapshot,
                &progress
              )
              persist_reader_snapshot(reader_snapshot, **payload)
            end
          end

          if @instrumentation
            @instrumentation.measure('pagination.build') { runner.call }
          else
            runner.call
          end

          presenter.update_status(progress: 1.0)
        # resilient-boundary
        rescue Shoko::Error => e
          raise if e.is_a?(Shoko::FatalExternalInputError)

          @logger&.error('CLI pagination prebuild failed', error: e.message)
        end

        def build_dynamic_pagination(width:, height:, document:, config_snapshot:, reader_snapshot:, progress:)
          payload = @page_calculator.build_dynamic_map!(
            width,
            height,
            document,
            config_reader: config_snapshot,
            sidebar_visible: reader_snapshot.sidebar_visible?,
            &progress
          )
          reader_snapshot = persist_reader_snapshot(
            reader_snapshot,
            total_pages: payload[:total_pages],
            last_width: payload[:last_width],
            last_height: payload[:last_height]
          )

          restore = @page_calculator.apply_pending_precise_restore!(reader_snapshot)
          return reader_snapshot unless restore

          updates = {}
          index = restore[:current_page_index]
          updates[:current_page_index] = index if restore.key?(:current_page_index) && !index.nil?
          updates[:pending_progress] = nil if restore[:clear_pending_progress]
          persist_reader_snapshot(reader_snapshot, **updates)
        end

        def persist_reader_snapshot(reader_snapshot, **attributes)
          return reader_snapshot if attributes.empty?

          @reader_session_store.save(reader_snapshot.with(**attributes))
        end

        def validate_document_loader!
          return if @document_loader.is_a?(Shoko::Core::Ports::Outbound::DocumentLoader)

          raise ArgumentError, 'document_loader must implement Core::Ports::Outbound::DocumentLoader'
        end
      end
    end
  end
end
