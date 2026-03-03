# frozen_string_literal: true

require_relative 'contracts'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Manages progress overlay, throttled redraws, and pagination build flow.
          class ProgressOrchestration
            include Contracts::ProgressOrchestration

            Dependencies = Data.define(
              :menu_state_reader,
              :menu_runtime,
              :progress_presenters,
              :null_presenter,
              :pagination_orchestrator,
              :page_calculator,
              :config_reader,
              :reader_state_reader,
              :sidebar_state_reader,
              :state_writer,
              :pagination_cache_preloader,
              :runtime_config,
              :ui_state_reader,
              :clock,
              :logger
            ) do
              REQUIRED_FIELDS = %i[
                menu_state_reader
                menu_runtime
                progress_presenters
                null_presenter
                pagination_orchestrator
                ui_state_reader
                clock
              ].freeze

              def validate!
                values = to_h
                missing = REQUIRED_FIELDS.select { |field| values[field].nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing progress orchestration dependencies: #{missing.join(', ')}"
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @menu_state_reader = dependencies.menu_state_reader
              @menu_runtime = dependencies.menu_runtime
              @progress_presenters = dependencies.progress_presenters
              @null_presenter = dependencies.null_presenter
              @pagination_orchestrator = dependencies.pagination_orchestrator
              @page_calculator = dependencies.page_calculator
              @config_reader = dependencies.config_reader
              @reader_state_reader = dependencies.reader_state_reader
              @sidebar_state_reader = dependencies.sidebar_state_reader
              @state_writer = dependencies.state_writer
              @pagination_cache_preloader = dependencies.pagination_cache_preloader
              @runtime_config = dependencies.runtime_config
              @ui_state_reader = dependencies.ui_state_reader
              @clock = dependencies.clock
              @logger = dependencies.logger
            end

            def load_and_open_with_progress(path:, prepare_reader_launch:, run_reader:)
              return launch_without_overlay(path, prepare_reader_launch: prepare_reader_launch, run_reader: run_reader) if skip_progress_overlay?

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
            rescue StandardError => e
              @logger&.debug('menu.progress_orchestration.cached_pagination_preload_failed',
                             error: e.class.name, message: e.message)
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
              index = @menu_state_reader.selected_library_index || 0
              mode = @menu_state_reader.current_menu_mode
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
              calculator = @page_calculator
              return unless calculator
              return unless width && height

              session = @pagination_orchestrator.session(
                doc: document,
                page_calculator: calculator,
                dimensions: [width, height],
                config_reader: @config_reader,
                reader_state_reader: @reader_state_reader,
                pagination_state_writer: @state_writer,
                ui_loading_writer: @state_writer,
                sidebar_state_reader: @sidebar_state_reader
              )
              return unless session

              presenter.update_message('Calculating pages...')
              @menu_runtime.draw_screen

              session.build_full_map! do |done, total|
                presenter.update(done: done, total: total)
                @menu_runtime.draw_screen
              end
              presenter.update(done: 1, total: 1)
            end

            def progress_reporter_for(presenter)
              last_update = nil
              lambda do |message: nil, progress: nil|
                changed = presenter.update_status(message: message, progress: progress)
                return unless changed

                now = @clock.monotonic_now
                if last_update.nil? || (now - last_update) >= 0.05
                  @menu_runtime.draw_screen
                  last_update = now
                end
              end
            end

            def terminal_dimensions
              width = @ui_state_reader&.terminal_width.to_i
              height = @ui_state_reader&.terminal_height.to_i
              width = 80 if width <= 0
              height = 24 if height <= 0
              [width, height]
            end
          end
        end
      end
    end
  end
end
