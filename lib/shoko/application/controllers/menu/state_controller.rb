# frozen_string_literal: true

require_relative '../../main_menu/menu_progress_presenter'
require_relative '../../workflows/menu/reader_launch_service'
require_relative '../../workflows/menu/download_workflow'
require_relative '../../workflows/menu/dictionary_workflow'
require_relative '../../workflows/menu/annotation_workflow'

module Shoko
  module Application::Controllers
    module Menu
      # Coordinates menu workflows while keeping all heavy logic in dedicated services.
      class StateController
        def initialize(menu, pagination_orchestrator:, download_service: nil,
                       dictionary_catalog_service: nil, logger: nil,
                       text_sanitizer: nil, background_worker_factory: nil,
                       recent_files_repository: nil, cache_pointer_resolver: nil,
                       dictionary_availability: nil, dictionary_storage: nil,
                       page_calculator: nil,
                       layout_service: nil, wrapping_service: nil,
                       document_service_factory: nil, config_reader: nil,
                       reader_state_reader: nil, state_writer: nil,
                       pagination_cache_preloader: nil, runtime_config: nil,
                       reader_session_context:, menu_session_context:,
                       annotation_service: nil,
                       selected_book_reader: nil,
                       annotation_selection_reader: nil,
                       annotation_view_refresher: nil,
                       build_reader_controller: nil,
                       document: nil, menu_state_reader: nil,
                       menu_state_writer: nil, file_probe: nil, path_ops: nil,
                       clock: nil, process_control: nil)
          @menu = menu
          @menu_state_reader = menu_state_reader
          @menu_state_writer = menu_state_writer
          @download_service = download_service
          @dictionary_catalog_service = dictionary_catalog_service
          @logger = logger
          @text_sanitizer = text_sanitizer
          @background_worker_factory = background_worker_factory
          @recent_files_repository = recent_files_repository
          @cache_pointer_resolver = cache_pointer_resolver
          @dictionary_availability = dictionary_availability
          @dictionary_storage = dictionary_storage
          @page_calculator = page_calculator
          @document_service_factory = document_service_factory
          @config_reader = config_reader
          @reader_state_reader = reader_state_reader
          @state_writer = state_writer
          @pagination_cache_preloader = pagination_cache_preloader
          @runtime_config = runtime_config
          @annotation_service = annotation_service
          @selected_book_reader = selected_book_reader
          @annotation_selection_reader = annotation_selection_reader
          @annotation_view_refresher = annotation_view_refresher
          @build_reader_controller = build_reader_controller
          @file_probe = file_probe
          @path_ops = path_ops
          raise ArgumentError, 'pagination_orchestrator is required' if pagination_orchestrator.nil?

          @pagination_orchestrator = pagination_orchestrator
          raise ArgumentError, 'clock is required' if clock.nil?
          raise ArgumentError, 'reader_session_context is required' if reader_session_context.nil?
          raise ArgumentError, 'menu_session_context is required' if menu_session_context.nil?

          @clock = clock
          @process_control = process_control
          @reader_session_context = reader_session_context
          @menu_session_context = menu_session_context
          @reader_session_context.document = document if document

          @reader_launch_service = build_reader_launch_service
          @download_workflow = build_download_workflow
          @dictionary_workflow = build_dictionary_workflow
          @annotation_workflow = build_annotation_workflow
        end

        def open_selected_book
          @reader_launch_service.open_selected_book
        end

        def open_book(path)
          @reader_launch_service.open_book(path)
        end

        def run_reader(path)
          @reader_launch_service.run_reader(path)
        end

        def load_and_open_with_progress(path)
          @reader_launch_service.load_and_open_with_progress(path)
        end

        def file_not_found
          @reader_launch_service.file_not_found
        end

        def handle_reader_error(path, error)
          @reader_launch_service.handle_reader_error(path, error)
        end

        def valid_cache_path?(path)
          @reader_launch_service.valid_cache_path?(path)
        end

        def refresh_scan(force: false)
          catalog.start_scan(force: force)
        end

        def search_downloads(query:, page_url: nil)
          @download_workflow.search_downloads(query: query, page_url: page_url)
        end

        def download_book(book)
          @download_workflow.download_book(book)
        end

        def fetch_dictionary_catalog
          @dictionary_workflow.fetch_dictionary_catalog
        end

        def download_dictionary(entry)
          @dictionary_workflow.download_dictionary(entry)
        end

        def open_selected_annotation
          @annotation_workflow.open_selected_annotation
        end

        def open_selected_annotation_for_edit
          @annotation_workflow.open_selected_annotation_for_edit
        end

        def delete_selected_annotation
          @annotation_workflow.delete_selected_annotation
        end

        def save_current_annotation_edit
          @annotation_workflow.save_current_annotation_edit
        end

        private

        attr_reader :menu, :menu_state_reader, :menu_state_writer

        # Backward-compatible private helper used by existing specs.
        def ensure_reader_document_for(path)
          @reader_launch_service.ensure_reader_document_for(path)
        end

        def catalog
          menu.catalog
        end

        def progress_presenter
          @progress_presenter ||= Application::MainMenu::MenuProgressPresenter.new(@menu_state_writer)
        end

        def read_selected_book
          return nil unless @selected_book_reader.respond_to?(:call)

          @selected_book_reader.call
        rescue StandardError
          nil
        end

        def read_selected_annotation_context
          return [nil, nil] unless @annotation_selection_reader.respond_to?(:call)

          selection = @annotation_selection_reader.call
          if selection.is_a?(Array)
            [selection[0], selection[1]]
          elsif selection.is_a?(Hash)
            [selection[:annotation] || selection['annotation'],
             selection[:book_path] || selection['book_path']]
          else
            [nil, nil]
          end
        rescue StandardError
          [nil, nil]
        end

        def refresh_annotations_view
          return unless @annotation_view_refresher.respond_to?(:call)

          @annotation_view_refresher.call
        rescue StandardError
          nil
        end

        def build_reader_launch_service
          Shoko::Application::Workflows::Menu::ReaderLaunchService.new(
            menu_state_reader: @menu_state_reader,
            reader_state_reader: @reader_state_reader,
            state_writer: @state_writer,
            runtime_config: @runtime_config,
            reader_session_context: @reader_session_context,
            menu_session_context: @menu_session_context,
            page_calculator: @page_calculator,
            pagination_orchestrator: @pagination_orchestrator,
            pagination_cache_preloader: @pagination_cache_preloader,
            document_service_factory: @document_service_factory,
            config_reader: @config_reader,
            background_worker_factory: @background_worker_factory,
            recent_files_repository: @recent_files_repository,
            cache_pointer_resolver: @cache_pointer_resolver,
            logger: @logger,
            terminal_service: menu.terminal_service,
            catalog: catalog,
            draw_screen: -> { menu.draw_screen },
            switch_mode: ->(mode) { menu.switch_to_mode(mode) },
            build_reader_controller: lambda do |reader_path, preloaded_document:, background_worker:|
              @build_reader_controller&.call(
                reader_path,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              )
            end,
            selected_book_reader: method(:read_selected_book),
            filtered_books_reader: -> { menu.filtered_epubs },
            progress_presenter_factory: -> { progress_presenter },
            file_probe: @file_probe,
            clock: @clock
          )
        end

        def build_download_workflow
          Shoko::Application::Workflows::Menu::DownloadWorkflow.new(
            download_service: @download_service,
            menu_state_writer: @menu_state_writer,
            draw_screen: -> { menu.draw_screen },
            refresh_scan: ->(force:) { refresh_scan(force: force) },
            text_sanitizer: @text_sanitizer,
            path_ops: @path_ops,
            clock: @clock
          )
        end

        def build_dictionary_workflow
          Shoko::Application::Workflows::Menu::DictionaryWorkflow.new(
            dictionary_catalog_service: @dictionary_catalog_service,
            dictionary_storage: @dictionary_storage,
            config_reader: @config_reader,
            menu_state_reader: @menu_state_reader,
            menu_state_writer: @menu_state_writer,
            draw_screen: -> { menu.draw_screen },
            file_probe: @file_probe,
            path_ops: @path_ops,
            clock: @clock
          )
        end

        def build_annotation_workflow
          Shoko::Application::Workflows::Menu::AnnotationWorkflow.new(
            menu: menu,
            menu_state_reader: @menu_state_reader,
            menu_state_writer: @menu_state_writer,
            state_writer: @state_writer,
            annotation_service: @annotation_service,
            logger: @logger,
            selected_annotation_reader: method(:read_selected_annotation_context),
            refresh_annotations_view: method(:refresh_annotations_view),
            run_reader: method(:run_reader)
          )
        end
      end
    end
  end
end
