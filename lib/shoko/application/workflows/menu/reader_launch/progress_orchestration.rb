# frozen_string_literal: true

require_relative 'contracts'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Manages progress overlay and pagination build flow.
          class ProgressOrchestration
            include Contracts::ProgressOrchestration

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
              progress_reporter = progress_reporter_for(presenter)
              document = load_document.call(path, progress_reporter)

              register_document.call(document)
              update_total_chapters.call(document)

              if document_cached?(document)
                preload_cached_pagination(document, width:, height:)
                return path
              end

              build_pagination(document, width, height, presenter)
              nil
            end

            def preload_cached_pagination(document, width:, height:)
              return unless @pagination_cache_preloader

              @pagination_cache_preloader.preload(document, width:, height:)
            # resilient-boundary
            rescue Shoko::Error => e
              @logger&.debug('menu.progress_orchestration.cached_pagination_preload_failed',
                             error: e.class.name,
                             message: e.message)
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

            def launch_with_overlay(path, prepare_reader_launch:, run_reader:)
              menu_snapshot = @menu_session_store.load
              index = menu_snapshot.browse_selected || 0
              mode = menu_snapshot.mode
              @active_presenter = @progress_presenters.build
              @active_presenter.show(path: path, index: index, mode: mode)

              target_path = nil
              begin
                target_path = prepare_reader_launch.call(path, @active_presenter)
              ensure
                @active_presenter.clear
              end

              run_reader.call(target_path || path)
            ensure
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
              session = pagination_session(document, width, height)
              return unless session

              presenter.update_message('Calculating pages...')
              build_full_pagination(session, presenter)
            end

            def progress_reporter_for(presenter)
              Class.new do
                def initialize(presenter:)
                  @presenter = presenter
                end

                def update_status(message: nil, progress: nil)
                  @presenter.update_status(message: message, progress: progress)
                end
              end
              .new(presenter: presenter)
            end

            def terminal_dimensions
              size = @reader_runtime_context.terminal_size
              [size.width, size.height]
            end

            def pagination_session(document, width, height)
              calculator = @page_calculator
              return unless calculator && width && height

              @pagination_orchestrator.session(
                doc: document,
                page_calculator: calculator,
                dimensions: [width, height],
                app_config_store: @app_config_store,
                reader_session_store: @reader_session_store,
                reader_view_state_store: @reader_view_state_store,
                reader_pagination_store: @reader_pagination_store
              )
            end

            def build_full_pagination(session, presenter)
              session.build_full_map! do |done, total|
                presenter.update(done: done, total: total)
              end
              presenter.update(done: 1, total: 1)
            end
          end
        end
      end
    end
  end
end
