# frozen_string_literal: true

require_relative 'reader_launch_bridges'
require_relative 'menu_workflow_bridges'

module Shoko
  module Adapters::Input::Controllers
    module Menu
      # Coordinates menu workflows while keeping all heavy logic in dedicated services.
      class StateController
        def initialize(
          menu,
          **deps
        )
          @menu = menu
          @menu_state_reader = deps[:menu_state_reader]
          @menu_state_writer = deps[:menu_state_writer]
          @download_service = deps[:download_service]
          @dictionary_catalog_service = deps[:dictionary_catalog_service]
          @logger = deps[:logger]
          @text_sanitizer = deps[:text_sanitizer]
          @background_worker_factory = deps[:background_worker_factory]
          @recent_files_repository = deps[:recent_files_repository]
          @cache_pointer_resolver = deps[:cache_pointer_resolver]
          @document_path_resolver = deps[:document_path_resolver]
          @dictionary_availability = deps[:dictionary_availability]
          @dictionary_storage = deps[:dictionary_storage]
          @page_calculator = deps[:page_calculator]
          @document_service_factory = deps[:document_service_factory]
          @config_reader = deps[:config_reader]
          @reader_state_reader = deps[:reader_state_reader]
          @state_writer = deps[:state_writer]
          @pagination_cache_preloader = deps[:pagination_cache_preloader]
          @runtime_config = deps[:runtime_config]
          @annotation_service = deps[:annotation_service]
          @selected_book_reader = deps[:selected_book_reader]
          @annotation_selection_reader = deps[:annotation_selection_reader]
          @annotation_view_refresher = deps[:annotation_view_refresher]
          @build_reader_controller = deps[:build_reader_controller]
          @file_probe = deps[:file_probe]
          @path_ops = deps[:path_ops]
          @process_control = deps[:process_control]

          @reader_launch_service_factory = deps[:reader_launch_service_factory]
          @download_workflow_factory = deps[:download_workflow_factory]
          @dictionary_workflow_factory = deps[:dictionary_workflow_factory]
          @annotation_workflow_factory = deps[:annotation_workflow_factory]
          @progress_presenter_factory = deps[:progress_presenter_factory]

          pagination_orchestrator = deps[:pagination_orchestrator]
          clock = deps[:clock]
          reader_session_context = deps[:reader_session_context]
          menu_session_context = deps[:menu_session_context]

          raise ArgumentError, 'pagination_orchestrator is required' if pagination_orchestrator.nil?
          raise ArgumentError, 'clock is required' if clock.nil?
          raise ArgumentError, 'reader_session_context is required' if reader_session_context.nil?
          raise ArgumentError, 'menu_session_context is required' if menu_session_context.nil?

          assert_callable!(@reader_launch_service_factory, :reader_launch_service_factory)
          assert_callable!(@download_workflow_factory, :download_workflow_factory)
          assert_callable!(@dictionary_workflow_factory, :dictionary_workflow_factory)
          assert_callable!(@annotation_workflow_factory, :annotation_workflow_factory)
          assert_callable!(@progress_presenter_factory, :progress_presenter_factory)

          @pagination_orchestrator = pagination_orchestrator
          @clock = clock
          @reader_session_context = reader_session_context
          @menu_session_context = menu_session_context
          document = deps[:document]
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

        def catalog
          menu.catalog
        end

        def progress_presenter
          @progress_presenter ||= @progress_presenter_factory.call
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
          @reader_launch_service_factory.call(
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
            document_path_resolver: @document_path_resolver,
            logger: @logger,
            terminal_service: menu.terminal_service,
            catalog: catalog,
            menu_runtime: reader_launch_runtime_bridge,
            book_selection: reader_launch_book_selection_bridge,
            progress_presenters: reader_launch_progress_presenters,
            file_probe: @file_probe,
            clock: @clock
          )
        end

        def reader_launch_runtime_bridge
          @reader_launch_runtime_bridge ||= ReaderLaunchRuntimeBridge.new(
            menu: menu,
            reader_controller_builder: @build_reader_controller
          )
        end

        def reader_launch_book_selection_bridge
          @reader_launch_book_selection_bridge ||= ReaderLaunchBookSelectionBridge.new(
            selected_book_reader: method(:read_selected_book),
            filtered_books_reader: -> { menu.filtered_epubs }
          )
        end

        def reader_launch_progress_presenters
          @reader_launch_progress_presenters ||= ReaderLaunchProgressPresenters.new(
            presenter_builder: -> { progress_presenter }
          )
        end

        def build_download_workflow
          @download_workflow_factory.call(
            download_service: @download_service,
            menu_state_writer: @menu_state_writer,
            menu_runtime: menu_workflow_runtime_bridge,
            text_sanitizer: @text_sanitizer,
            path_ops: @path_ops,
            clock: @clock
          )
        end

        def build_dictionary_workflow
          @dictionary_workflow_factory.call(
            dictionary_catalog_service: @dictionary_catalog_service,
            dictionary_storage: @dictionary_storage,
            config_reader: @config_reader,
            menu_state_reader: @menu_state_reader,
            menu_state_writer: @menu_state_writer,
            menu_runtime: menu_workflow_runtime_bridge,
            file_probe: @file_probe,
            path_ops: @path_ops,
            clock: @clock
          )
        end

        def menu_workflow_runtime_bridge
          @menu_workflow_runtime_bridge ||= MenuWorkflowRuntimeBridge.new(
            menu: menu,
            catalog: catalog
          )
        end

        def build_annotation_workflow
          @annotation_workflow_factory.call(
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

        def assert_callable!(value, name)
          return if value.respond_to?(:call)

          raise ArgumentError, "#{name} is required and must respond to :call"
        end
      end
    end
  end
end
