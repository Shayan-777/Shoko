# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_reader_runtime'
require_relative '../../../core/ports/outbound/menu_book_selection'
require_relative '../../../core/ports/outbound/menu_progress_presenters'
require_relative '../../../core/ports/outbound/menu_workflow_state_reader'
require_relative '../../../core/services/document_path_resolver'
require_relative 'null_progress_presenter'

module Shoko
  module Application
    module Workflows
      module Menu
        class ReaderLaunchService
          Dependencies = Data.define(
            :menu_state_reader,
            :reader_state_reader,
            :state_writer,
            :runtime_config,
            :reader_session_context,
            :menu_session_context,
            :page_calculator,
            :pagination_orchestrator,
            :pagination_cache_preloader,
            :document_service_factory,
            :config_reader,
            :background_worker_factory,
            :recent_files_repository,
            :cache_pointer_resolver,
            :document_path_resolver,
            :logger,
            :terminal_service,
            :catalog,
            :menu_runtime,
            :book_selection,
            :progress_presenters,
            :file_probe,
            :path_ops,
            :clock
          ) do
            REQUIRED_FIELDS = %i[
              menu_state_reader
              reader_state_reader
              state_writer
              reader_session_context
              menu_session_context
              pagination_orchestrator
              terminal_service
              catalog
              menu_runtime
              book_selection
              progress_presenters
              clock
            ].freeze

            def validate!
              missing = REQUIRED_FIELDS.select { |field| public_send(field).nil? }
              unless missing.empty?
                raise ArgumentError, "Missing required reader launch dependencies: #{missing.join(', ')}"
              end

              unless menu_runtime.is_a?(Shoko::Core::Ports::Outbound::MenuReaderRuntime)
                raise ArgumentError, 'menu_runtime must implement Core::Ports::Outbound::MenuReaderRuntime'
              end
              unless book_selection.is_a?(Shoko::Core::Ports::Outbound::MenuBookSelection)
                raise ArgumentError, 'book_selection must implement Core::Ports::Outbound::MenuBookSelection'
              end
              unless progress_presenters.is_a?(Shoko::Core::Ports::Outbound::MenuProgressPresenters)
                raise ArgumentError, 'progress_presenters must implement Core::Ports::Outbound::MenuProgressPresenters'
              end
              unless menu_state_reader.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateReader)
                raise ArgumentError, 'menu_state_reader must implement Core::Ports::Outbound::MenuWorkflowStateReader'
              end

              self
            end
          end

          def initialize(deps:)
            deps.validate!

            @menu_state_reader = deps.menu_state_reader
            @reader_state_reader = deps.reader_state_reader
            @state_writer = deps.state_writer
            @runtime_config = deps.runtime_config
            @reader_session_context = deps.reader_session_context
            @menu_session_context = deps.menu_session_context
            @page_calculator = deps.page_calculator
            @pagination_orchestrator = deps.pagination_orchestrator
            @pagination_cache_preloader = deps.pagination_cache_preloader
            @document_service_factory = deps.document_service_factory
            @config_reader = deps.config_reader
            @background_worker_factory = deps.background_worker_factory
            @recent_files_repository = deps.recent_files_repository
            @cache_pointer_resolver = deps.cache_pointer_resolver
            @document_path_resolver = deps.document_path_resolver
            @logger = deps.logger
            @terminal_service = deps.terminal_service
            @catalog = deps.catalog
            @menu_runtime = deps.menu_runtime
            @book_selection = deps.book_selection
            @progress_presenters = deps.progress_presenters
            @file_probe = deps.file_probe
            @path_ops = deps.path_ops
            @clock = deps.clock

            @document_path_resolver ||= Shoko::Core::Services::DocumentPathResolver.new(
              cache_pointer_resolver: @cache_pointer_resolver,
              path_ops: @path_ops,
              logger: @logger
            )
            @null_presenter = Shoko::Application::Workflows::Menu::NullProgressPresenter.new
            @document = @reader_session_context&.document
          end

          def open_selected_book
            book = @book_selection.selected_book
            book ||= begin
              idx = @menu_state_reader.selected_library_index
              books = @book_selection.filtered_books
              books && books[idx]
            end

            return unless book

            path = book['path']
            if path && file_exists?(path)
              load_and_open_with_progress(path)
            else
              file_not_found
            end
          end

          def open_book(path)
            return file_not_found unless file_exists?(path)

            load_and_open_with_progress(path)
          # resilient-boundary
          rescue StandardError => e
            handle_reader_error(path, e)
          end

          def run_reader(path)
            prior_mode = @menu_state_reader.current_menu_mode
            reader_path = canonical_path(path)

            return unless ensure_reader_document_for(reader_path)

            recent_path = canonical_recent_path(reader_path)
            @recent_files_repository&.add(recent_path) if recent_path

            @logger&.debug('menu.run_reader.dispatch_running', path: reader_path, running: true)
            @state_writer.update_reader_meta(book_path: reader_path, running: true)
            @state_writer.update_reader(mode: :read)

            running_after = @reader_state_reader.running?
            @logger&.debug('menu.run_reader.after_dispatch', running_value: running_after)

            @menu_session_context.last_opened_path = reader_path
            @menu_runtime.run_reader(
              path: reader_path,
              preloaded_document: @document,
              background_worker: current_background_worker
            )
          # resilient-boundary
          rescue StandardError => e
            @logger&.error('menu.run_reader.exception', error: e.class.name, message: e.message)
            raise
          ensure
            @logger&.debug('menu.run_reader.ensure', prior_mode: prior_mode)
            @document = nil
            @reader_session_context.document = nil
            @terminal_service&.ensure_session_depth(1) if @terminal_service.respond_to?(:ensure_session_depth)
            @menu_runtime.switch_mode(prior_mode || :browse)
          end

          def load_and_open_with_progress(path)
            return launch_without_overlay(path) if skip_progress_overlay?

            launch_with_overlay(path)
          end

          def file_not_found
            @catalog.update_scan_state(status: :error, message: 'File not found')
          end

          def handle_reader_error(path, error)
            @logger&.error('Failed to open book', error: error.message, path: path)
            @catalog.update_scan_state(
              status: :error,
              message: "Failed: #{error.class}: #{error.message[0, 60]}"
            )

            return unless @logger.respond_to?(:debug)

            @logger&.debug('Reader error backtrace',
                           path: path,
                           backtrace: Array(error.backtrace).join("\n"))
          end

          def valid_cache_path?(path)
            return false unless path && file_regular?(path)
            return false unless cache_pointer?(path)

            !!cache_payload(path, strict: true)
          # resilient-boundary
          rescue StandardError => e
            @logger&.debug('menu.valid_cache_path.failed', path: path, error: e.class.name, message: e.message)
            false
          end

          def ensure_reader_document_for(path)
            target_path = canonical_path(path)
            existing = @document
            return true if document_matches?(existing, target_path)

            document = load_document_for(target_path)
            register_document(document)
            update_total_chapters(document)
            true
          # resilient-boundary
          rescue StandardError => e
            handle_reader_error(path, e)
            false
          end

          private

          def canonical_recent_path(path)
            return path unless @document_path_resolver

            @document_path_resolver.resolve_source_path(path)
          end

          def cache_pointer?(path)
            @cache_pointer_resolver ? @cache_pointer_resolver.cache_pointer?(path) : false
          end

          def cache_payload(path, strict:)
            @cache_pointer_resolver&.read_cache(path, strict: strict)
          end

          def prepare_reader_launch(path, presenter)
            height, width = @terminal_service.size
            warm_launch_dependencies

            progress_reporter = progress_reporter_for(presenter)
            document = load_document_for(path, progress_reporter: progress_reporter)
            if document_cached?(document)
              register_document(document)
              update_total_chapters(document)
              preload_cached_pagination(document, width, height)
              return path
            end

            register_document(document)
            update_total_chapters(document)
            build_pagination(document, width, height, presenter)
            nil
          # resilient-boundary
          rescue StandardError => e
            handle_reader_error(path, e)
            nil
          end

          def warm_launch_dependencies
            page_calculator
            ensure_background_worker
          end

          def load_document_for(path, progress_reporter: nil)
            raise 'document_service_factory not available' unless @document_service_factory

            @document_service_factory.call(
              path,
              progress_reporter: progress_reporter,
              background_worker: current_background_worker
            ).load_document
          end

          def document_cached?(document)
            document.respond_to?(:cached?) && document.cached?
          end

          def register_document(document)
            @document = document
            @reader_session_context.document = document
          end

          def update_total_chapters(document)
            total = document&.chapter_count || 0
            @state_writer.update_pagination_state(total_chapters: total)
          end

          def ensure_background_worker
            return if current_background_worker

            worker = build_background_worker(name: 'document-preload')
            @reader_session_context.background_worker = worker if worker
          # resilient-boundary
          rescue StandardError => e
            @logger&.debug('menu.ensure_background_worker.failed', error: e.class.name, message: e.message)
            nil
          end

          def build_pagination(document, width, height, presenter)
            calculator = page_calculator
            return unless calculator
            return unless width && height

            session = @pagination_orchestrator.session(
              doc: document,
              page_calculator: calculator,
              dimensions: [width, height],
              config_reader: @config_reader,
              reader_state_reader: @reader_state_reader,
              state_writer: @state_writer
            )
            return unless session

            if presenter.respond_to?(:update_message)
              presenter.update_message('Calculating pages...')
              @menu_runtime.draw_screen
            end

            session.build_full_map! do |done, total|
              presenter.update(done: done, total: total)
              @menu_runtime.draw_screen
            end
            presenter.update(done: 1, total: 1)
          end

          def progress_reporter_for(presenter)
            return nil unless presenter.respond_to?(:update_status)

            last_update = nil
            lambda do |message: nil, progress: nil|
              changed = presenter.update_status(message: message, progress: progress)
              return unless changed

              now = monotonic_now
              if last_update.nil? || (now - last_update) >= 0.05
                @menu_runtime.draw_screen
                last_update = now
              end
            end
          end

          def skip_progress_overlay?
            return @runtime_config.skip_progress_overlay? if @runtime_config

            false
          end

          def page_calculator
            @page_calculator
          end

          def preload_cached_pagination(document, width, height)
            preloader = @pagination_cache_preloader
            return unless preloader

            preloader.preload(document, width:, height:)
          # resilient-boundary
          rescue StandardError => e
            @logger&.debug('ReaderLaunchService: cached pagination preload failed', error: e.message)
            nil
          end

          def launch_without_overlay(path)
            warm_launch_dependencies
            target_path = prepare_reader_launch(path, @null_presenter)
            run_reader(target_path || path)
          # resilient-boundary
          rescue StandardError => e
            handle_reader_error(path, e)
          end

          def launch_with_overlay(path)
            index = @menu_state_reader.selected_library_index || 0
            mode = @menu_state_reader.current_menu_mode
            presenter = @progress_presenters.build
            presenter.show(path: path, index: index, mode: mode)

            target_path = nil
            begin
              target_path = prepare_reader_launch(path, presenter)
            ensure
              presenter.clear
            end

            run_reader(target_path || path)
          end

          def build_background_worker(name:)
            factory = @background_worker_factory
            return nil unless factory

            factory.call(logger: @logger, name: name)
          rescue ArgumentError
            # Backward compatibility for factories that only accept name.
            factory.call(name: name)
          # resilient-boundary
          rescue StandardError => e
            @logger&.debug('menu.build_background_worker.failed', error: e.class.name, message: e.message)
            nil
          end

          def current_background_worker
            @reader_session_context.background_worker
          end

          def file_exists?(path)
            @file_probe&.exist?(path)
          end

          def file_regular?(path)
            @file_probe&.file?(path)
          end

          def monotonic_now
            @clock.monotonic_now
          end

          def canonical_path(path)
            @document_path_resolver.canonical_reader_path(path) || path
          end

          def document_matches?(document, target_path)
            @document_path_resolver.document_matches_path?(document, target_path)
          end
        end
      end
    end
  end
end
