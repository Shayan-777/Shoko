# frozen_string_literal: true

require_relative 'cli_progress_presenter'
require_relative '../../application/ports/outbound/document_loader'
require_relative '../../core/services/progress_ratio'

module Shoko
  module Adapters
    module Runtime
      # Adapter-owned reader startup/runtime orchestration.
      class ReaderModeRunner
        PaginationContext = Data.define(:document, :config_snapshot, :reader_snapshot, :width, :height)

        ProgressReporter = Data.define(:presenter) do
          def update_status(message: nil, progress: nil)
            presenter.update_status(message: message, progress: progress)
          end
        end

        def initialize(build_reader_controller:, terminal_session:, instrumentation_service:, cache_availability:,
                       document_loader:, cli_progress_renderer:, page_calculator:, app_config_store:,
                       reader_session_store:, reader_pagination_store:, reader_runtime_context:,
                       reader_launch_state:, instrumentation:, logger:)
          @build_reader_controller = build_reader_controller
          @terminal_session = terminal_session
          @instrumentation_service = instrumentation_service
          @cache_availability = cache_availability
          @document_loader = document_loader
          @cli_progress_renderer = cli_progress_renderer
          @page_calculator = page_calculator
          @app_config_store = app_config_store
          @reader_session_store = reader_session_store
          @reader_pagination_store = reader_pagination_store
          @reader_runtime_context = reader_runtime_context
          @reader_launch_state = reader_launch_state
          @instrumentation = instrumentation
          @logger = logger
        end

        def run(path:)
          @instrumentation_service&.start_trace(path)
          preload_document_if_needed(path)
          # setup runs inside the begin so a failure mid-setup (raw mode entered,
          # then a crash before the alt-screen/cursor are restored) still reaches
          # cleanup and leaves the terminal usable — matching the menu run loop.
          # Previously a setup-time raise on the direct `bin/shoko <file>` path
          # left the terminal raw + alt-screen because cleanup was never entered.
          begin
            @terminal_session.setup
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
          @reader_launch_state.preloaded_document = document if @reader_launch_state && document
          build_cli_pagination(document, presenter)
        ensure
          presenter&.finish
        end

        def build_cli_pagination(document, presenter)
          context = pagination_context_for(document)
          return unless context

          presenter.update_status(message: 'Calculating pages...', progress: 0.0)
          with_pagination_measurement { build_cli_pages(context, presenter_progress_callback(presenter)) }
          presenter.update_status(progress: 1.0)
        # resilient-boundary
        rescue StandardError => e
          raise if e.is_a?(Shoko::FatalExternalInputError)

          record_cli_pagination_error(e)
        end

        def record_cli_pagination_error(error)
          @logger&.error('CLI pagination prebuild failed',
                         error_class: error.class.name, error: error.message)
        end

        def build_dynamic_pagination(width:, height:, document:, config_snapshot:, reader_snapshot:, progress:)
          payload = @page_calculator.build_dynamic_map!(
            width,
            height,
            document,
            config_reader: config_snapshot,
            &progress
          )
          persist_dynamic_payload(payload)
          apply_dynamic_restore(reader_snapshot)
        end

        def persist_reader_snapshot(reader_snapshot, **attributes)
          return reader_snapshot if attributes.empty?

          @reader_session_store.save(reader_snapshot.with(**attributes))
        end

        def pagination_context_for(document)
          return unless document
          return if document.cached?
          return unless pagination_dependencies_available?

          width, height = terminal_dimensions
          return unless width && height

          PaginationContext.new(
            document: document,
            config_snapshot: @app_config_store.load,
            reader_snapshot: @reader_session_store.load,
            width: width,
            height: height
          )
        end

        def pagination_dependencies_available?
          @page_calculator && @app_config_store && @reader_session_store && @reader_runtime_context
        end

        def terminal_dimensions
          size = @reader_runtime_context.terminal_size
          [size.width, size.height]
        end

        def presenter_progress_callback(presenter)
          lambda do |done, total|
            presenter.update_status(
              message: pagination_progress_message(done, total),
              progress: Shoko::Core::Services::ProgressRatio.compute(done, total)
            )
          end
        end

        def pagination_progress_message(done, total)
          total_i = total.to_i
          return 'Calculating pages...' unless total_i.positive?

          "Calculating pages (#{done.to_i}/#{total_i})..."
        end

        def build_cli_pages(context, progress)
          return build_dynamic_cli_pages(context, progress) if context.config_snapshot.page_numbering_mode == :dynamic

          build_absolute_cli_pages(context, progress)
        end

        def with_pagination_measurement(&)
          return yield unless @instrumentation

          @instrumentation.measure('pagination.build', &)
        end

        # Page-map dimensions are pagination state, not session state: they
        # live on the pagination snapshot (the session snapshot has no such
        # fields and rejects them).
        def persist_dynamic_payload(payload)
          pagination = @reader_pagination_store.load
          @reader_pagination_store.save(
            pagination.with(
              total_pages: payload[:total_pages].to_i,
              last_width: payload[:last_width].to_i,
              last_height: payload[:last_height].to_i
            )
          )
        end

        def apply_dynamic_restore(reader_snapshot)
          restore = @page_calculator.apply_pending_precise_restore!(reader_snapshot)
          return reader_snapshot unless restore

          persist_reader_snapshot(reader_snapshot, **dynamic_restore_updates(restore))
        end

        def dynamic_restore_updates(restore)
          updates = {}
          index = restore[:current_page_index]
          updates[:current_page_index] = index if restore.key?(:current_page_index) && !index.nil?
          updates[:pending_progress] = nil if restore[:clear_pending_progress]
          updates
        end

        def build_dynamic_cli_pages(context, progress)
          build_dynamic_pagination(
            width: context.width,
            height: context.height,
            document: context.document,
            config_snapshot: context.config_snapshot,
            reader_snapshot: context.reader_snapshot,
            progress: progress
          )
        end

        def build_absolute_cli_pages(context, progress)
          payload = @page_calculator.build_absolute_map!(
            context.width,
            context.height,
            context.document,
            config_reader: context.config_snapshot,
            &progress
          )
          persist_reader_snapshot(context.reader_snapshot, **payload)
        end

        def validate_document_loader!
          return if @document_loader.is_a?(Shoko::Application::Ports::Outbound::DocumentLoader)

          raise ArgumentError, 'document_loader must implement Application::Ports::Outbound::DocumentLoader'
        end
      end
    end
  end
end
