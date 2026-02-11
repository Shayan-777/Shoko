# frozen_string_literal: true

require_relative '../../controllers/document_path_resolver'
require_relative 'null_progress_presenter'

module Shoko
  module Application
    module Workflows
      module Menu
        class ReaderLaunchService
          include Shoko::Application::Controllers::DocumentPathResolver

          def initialize(menu_state_reader:, reader_state_reader:, state_writer:, runtime_config:, reader_session_context:,
                         menu_session_context:, page_calculator:, pagination_orchestrator:, pagination_cache_preloader:,
                         document_service_factory:, config_reader:, background_worker_factory:,
                         recent_files_repository:, cache_pointer_resolver:, logger:, terminal_service:, catalog:,
                         draw_screen:, switch_mode:, build_reader_controller:, selected_book_reader:,
                         filtered_books_reader:, progress_presenter_factory:, file_probe: nil, clock: nil)
            @menu_state_reader = menu_state_reader
            @reader_state_reader = reader_state_reader
            @state_writer = state_writer
            @runtime_config = runtime_config
            @reader_session_context = reader_session_context
            @menu_session_context = menu_session_context
            @page_calculator = page_calculator
            @pagination_orchestrator = pagination_orchestrator
            @pagination_cache_preloader = pagination_cache_preloader
            @document_service_factory = document_service_factory
            @config_reader = config_reader
            @background_worker_factory = background_worker_factory
            @recent_files_repository = recent_files_repository
            @cache_pointer_resolver = cache_pointer_resolver
            @logger = logger
            @terminal_service = terminal_service
            @catalog = catalog
            @draw_screen = draw_screen
            @switch_mode = switch_mode
            @build_reader_controller = build_reader_controller
            @selected_book_reader = selected_book_reader
            @filtered_books_reader = filtered_books_reader
            @progress_presenter_factory = progress_presenter_factory
            @file_probe = file_probe
            @clock = clock
            @null_presenter = Shoko::Application::Workflows::Menu::NullProgressPresenter.new
            @document = @reader_session_context&.document
          end

          def open_selected_book
            book = read_selected_book
            book ||= begin
              idx = @menu_state_reader.browse_selected
              books = @filtered_books_reader.call
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
          rescue StandardError => e
            handle_reader_error(path, e)
          end

          def run_reader(path)
            prior_mode = @menu_state_reader.mode
            reader_path = canonical_reader_path(path) || path

            return unless ensure_reader_document_for(reader_path)

            recent_path = canonical_recent_path(reader_path)
            @recent_files_repository&.add(recent_path) if recent_path

            @logger&.debug('menu.run_reader.dispatch_running', path: reader_path, running: true)
            @state_writer.update_reader_meta(book_path: reader_path, running: true)
            @state_writer.update_reader(mode: :read)

            running_after = @reader_state_reader.running?
            @logger&.debug('menu.run_reader.after_dispatch', running_value: running_after)

            @menu_session_context.last_opened_path = reader_path
            @build_reader_controller.call(
              reader_path,
              preloaded_document: @document,
              background_worker: current_background_worker
            ).run
          rescue StandardError => e
            @logger&.error('menu.run_reader.exception', error: e.class.name, message: e.message)
            raise
          ensure
            @logger&.debug('menu.run_reader.ensure', prior_mode: prior_mode)
            @document = nil
            @reader_session_context.document = nil
            @terminal_service&.ensure_session_depth(1) if @terminal_service.respond_to?(:ensure_session_depth)
            @switch_mode.call(prior_mode || :browse)
          end

          def load_and_open_with_progress(path)
            return launch_without_overlay(path) if skip_progress_overlay?

            launch_with_overlay(path)
          end

          def file_not_found
            @catalog.scan_message = 'File not found'
            @catalog.scan_status = :error
          end

          def handle_reader_error(path, error)
            @logger&.error('Failed to open book', error: error.message, path: path)
            @catalog.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
            @catalog.scan_status = :error

            return unless @logger.respond_to?(:debug)

            @logger&.debug('Reader error backtrace',
                           path: path,
                           backtrace: Array(error.backtrace).join("\n"))
          end

          def valid_cache_path?(path)
            return false unless path && file_regular?(path)
            return false unless cache_pointer?(path)

            !!cache_payload(path, strict: true)
          rescue StandardError
            false
          end

          def ensure_reader_document_for(path)
            target_path = canonical_reader_path(path) || path
            existing = @document
            return true if document_matches_path?(existing, target_path)

            document = load_document_for(target_path)
            register_document(document)
            update_total_chapters(document)
            true
          rescue StandardError => e
            handle_reader_error(path, e)
            false
          end

          private

          def read_selected_book
            return nil unless @selected_book_reader.respond_to?(:call)

            @selected_book_reader.call
          rescue StandardError
            nil
          end

          def canonical_recent_path(path)
            resolve_source_path(path)
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
          rescue StandardError
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
              @draw_screen.call
            end

            session.build_full_map! do |done, total|
              presenter.update(done: done, total: total)
              @draw_screen.call
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
                @draw_screen.call
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
          rescue StandardError => e
            @logger&.debug('ReaderLaunchService: cached pagination preload failed', error: e.message)
            nil
          end

          def launch_without_overlay(path)
            warm_launch_dependencies
            target_path = prepare_reader_launch(path, @null_presenter)
            run_reader(target_path || path)
          rescue StandardError => e
            handle_reader_error(path, e)
          end

          def launch_with_overlay(path)
            index = @menu_state_reader.browse_selected || 0
            mode = @menu_state_reader.mode
            presenter = @progress_presenter_factory.call
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
            return nil unless factory.respond_to?(:call)

            factory.call(name:)
          rescue StandardError
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
            @clock ? @clock.monotonic_now : Time.now.to_f
          end
        end
      end
    end
  end
end
