# frozen_string_literal: true

require_relative 'contracts'
require 'shoko/core/services/progress_ratio'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Manages progress overlay and pagination build flow.
          #
          # The overlay shows ONE monotonic bar across every launch phase:
          # document load/import fills [0, LOAD_PROGRESS_SHARE] and pagination
          # fills the rest, so the bar never sits at a false 100% between
          # phases and only reaches 100% when nothing tracked remains.
          class ProgressOrchestration
            include Contracts::ProgressOrchestration

            LOAD_PROGRESS_SHARE = 0.7

            # Maps a phase-local 0..1 progress into the launch-wide bar segment.
            class ScaledProgressReporter
              def initialize(presenter:, from:, to:)
                @presenter = presenter
                @from = from
                @span = to - from
              end

              def update_status(message: nil, progress: nil)
                scaled = progress.nil? ? nil : @from + (progress.to_f.clamp(0.0, 1.0) * @span)
                @presenter.update_status(message: message, progress: scaled)
              end
            end

            PROGRESS_ORCHESTRATION_REQUIRED_FIELDS = %i[
              menu_session_store
              progress_presenters
              null_presenter
              pagination_orchestrator
              app_config_store
              reader_session_store
              reader_view_state_store
              reader_pagination_store
              reader_runtime_context
            ].freeze

            Dependencies = Data.define(
              :menu_session_store,
              :progress_presenters,
              :null_presenter,
              :pagination_orchestrator,
              :page_calculator,
              :app_config_store,
              :reader_session_store,
              :reader_view_state_store,
              :reader_pagination_store,
              :pagination_cache_preloader,
              :runtime_config,
              :reader_runtime_context,
              :logger
            ) do
              def validate!
                values = to_h
                missing = ProgressOrchestration::PROGRESS_ORCHESTRATION_REQUIRED_FIELDS.select do |field|
                  values[field].nil?
                end
                return self if missing.empty?

                raise ArgumentError, "Missing progress orchestration dependencies: #{missing.join(', ')}"
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @menu_session_store = dependencies.menu_session_store
              @progress_presenters = dependencies.progress_presenters
              @null_presenter = dependencies.null_presenter
              @pagination_orchestrator = dependencies.pagination_orchestrator
              @page_calculator = dependencies.page_calculator
              @app_config_store = dependencies.app_config_store
              @reader_session_store = dependencies.reader_session_store
              @reader_view_state_store = dependencies.reader_view_state_store
              @reader_pagination_store = dependencies.reader_pagination_store
              @pagination_cache_preloader = dependencies.pagination_cache_preloader
              @runtime_config = dependencies.runtime_config
              @reader_runtime_context = dependencies.reader_runtime_context
              @logger = dependencies.logger
            end

            def load_and_open_with_progress(path:, prepare_reader_launch:, run_reader:)
              if skip_progress_overlay?
                return launch_without_overlay(path,
                                              prepare_reader_launch: prepare_reader_launch,
                                              run_reader: run_reader)
              end

              launch_with_overlay(path, prepare_reader_launch: prepare_reader_launch, run_reader: run_reader)
            end

            def prepare_reader_launch(path:, load_document:, register_document:, update_total_chapters:, presenter:)
              width, height = terminal_dimensions
              progress_reporter = load_progress_reporter(presenter)
              document = load_document.call(path, progress_reporter)

              register_document.call(document)
              update_total_chapters.call(document)

              if document_cached?(document)
                preload_cached_pagination(document, width:, height:)
                presenter.update_status(progress: 1.0)
                return path
              end

              build_pagination(document, width, height, presenter)
              nil
            end

            # Warm-cache preload is best-effort: any failure here just means a
            # cold pagination later, so nothing may escape into the launch path.
            def preload_cached_pagination(document, width:, height:)
              return unless @pagination_cache_preloader

              @pagination_cache_preloader.preload(document, width:, height:)
            # resilient-boundary
            rescue StandardError => e
              swallow_pagination_preload_error(e)
            end

            def swallow_pagination_preload_error(error)
              @logger&.debug('menu.progress_orchestration.cached_pagination_preload_failed',
                             error: error.class.name,
                             message: error.message)
              nil
            end

            private

            def launch_without_overlay(path, prepare_reader_launch:, run_reader:)
              @active_presenter = @null_presenter
              target_path = prepare_reader_launch.call(path, @active_presenter)
              run_reader.call(target_path || path)
            ensure
              @active_presenter = nil
            end

            # The overlay's 100% frame stays on screen until the reader's first
            # paint replaces it: clearing before run_reader repainted the
            # browse screen between "100%" and the reader, which read as the
            # bar finishing early and the app hesitating.
            def launch_with_overlay(path, prepare_reader_launch:, run_reader:)
              menu_snapshot = @menu_session_store.load
              index = menu_snapshot.browse_selected || 0
              mode = menu_snapshot.mode
              @active_presenter = @progress_presenters.build
              @active_presenter.show(path: path, index: index, mode: mode)

              target_path = prepare_reader_launch.call(path, @active_presenter)
              run_reader.call(target_path || path)
            ensure
              @active_presenter&.clear
              @active_presenter = nil
            end

            def skip_progress_overlay?
              return @runtime_config.skip_progress_overlay? if @runtime_config

              false
            end

            def document_cached?(document)
              document.cached?
            end

            def build_pagination(document, width, height, presenter)
              runtime = pagination_runtime(document)
              return unless runtime

              presenter.update_message('Calculating pages...')
              build_full_pagination(runtime, width: width, height: height, presenter: presenter)
            end

            def load_progress_reporter(presenter)
              ScaledProgressReporter.new(presenter: presenter, from: 0.0, to: LOAD_PROGRESS_SHARE)
            end

            def terminal_dimensions
              size = @reader_runtime_context.terminal_size
              [size.width, size.height]
            end

            def pagination_runtime(document)
              calculator = @page_calculator
              return unless calculator

              @pagination_orchestrator.bind(
                doc: document,
                page_calculator: calculator,
                app_config_store: @app_config_store,
                reader_session_store: @reader_session_store,
                reader_view_state_store: @reader_view_state_store,
                reader_pagination_store: @reader_pagination_store
              )
            end

            def build_full_pagination(runtime, width:, height:, presenter:)
              reporter = ScaledProgressReporter.new(presenter: presenter, from: LOAD_PROGRESS_SHARE, to: 1.0)
              runtime.build_full_map(dimensions: [width, height]) do |done, total|
                reporter.update_status(progress: Shoko::Core::Services::ProgressRatio.compute(done, total))
              end
              presenter.update_status(progress: 1.0)
            end
          end
        end
      end
    end
  end
end
