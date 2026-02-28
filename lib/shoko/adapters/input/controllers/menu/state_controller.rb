# frozen_string_literal: true

require_relative 'reader_launch_bridges'
require_relative 'menu_workflow_bridges'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Coordinates menu workflows while keeping all heavy logic in dedicated services.
          class StateController
            Dependencies = Data.define(
              :menu_state_reader,
              :menu_state_writer,
              :download_service,
              :dictionary_catalog_service,
              :logger,
              :text_sanitizer,
              :background_worker_factory,
              :recent_files_repository,
              :cache_pointer_resolver,
              :document_path_resolver,
              :dictionary_availability,
              :dictionary_storage,
              :page_calculator,
              :document_service_factory,
              :config_reader,
              :reader_state_reader,
              :state_writer,
              :pagination_cache_preloader,
              :runtime_config,
              :annotation_service,
              :selected_book_reader,
              :annotation_selection_reader,
              :annotation_view_refresher,
              :build_reader_controller,
              :file_probe,
              :path_ops,
              :process_control,
              :reader_launch_dependencies_factory,
              :reader_launch_service_factory,
              :download_workflow_factory,
              :dictionary_workflow_factory,
              :annotation_workflow_factory,
              :progress_presenter_factory,
              :pagination_orchestrator,
              :clock,
              :reader_session_context,
              :menu_session_context,
              :document
            ) do
              REQUIRED_FIELDS = %i[
                menu_state_reader
                menu_state_writer
                state_writer
                selected_book_reader
                annotation_selection_reader
                annotation_view_refresher
                build_reader_controller
                reader_launch_dependencies_factory
                reader_launch_service_factory
                download_workflow_factory
                dictionary_workflow_factory
                annotation_workflow_factory
                progress_presenter_factory
                pagination_orchestrator
                clock
                reader_session_context
                menu_session_context
              ].freeze

              CALLABLE_FIELDS = %i[
                selected_book_reader
                annotation_selection_reader
                annotation_view_refresher
                build_reader_controller
                reader_launch_dependencies_factory
                reader_launch_service_factory
                download_workflow_factory
                dictionary_workflow_factory
                annotation_workflow_factory
                progress_presenter_factory
              ].freeze

              def validate!
                missing = REQUIRED_FIELDS.select { |field| public_send(field).nil? }
                unless missing.empty?
                  raise ArgumentError, "Missing required menu state controller dependencies: #{missing.join(', ')}"
                end

                CALLABLE_FIELDS.each do |field|
                  value = public_send(field)
                  next if value.respond_to?(:call)

                  raise ArgumentError, "#{field} is required and must respond to :call"
                end

                self
              end
            end

            def initialize(menu:, deps:)
              raise ArgumentError, 'menu is required' if menu.nil?
              raise ArgumentError, 'deps is required' if deps.nil?

              dependencies = deps.validate!

              @menu = menu
              @menu_state_reader = dependencies.menu_state_reader
              @menu_state_writer = dependencies.menu_state_writer
              @download_service = dependencies.download_service
              @dictionary_catalog_service = dependencies.dictionary_catalog_service
              @logger = dependencies.logger
              @text_sanitizer = dependencies.text_sanitizer
              @background_worker_factory = dependencies.background_worker_factory
              @recent_files_repository = dependencies.recent_files_repository
              @cache_pointer_resolver = dependencies.cache_pointer_resolver
              @document_path_resolver = dependencies.document_path_resolver
              @dictionary_availability = dependencies.dictionary_availability
              @dictionary_storage = dependencies.dictionary_storage
              @page_calculator = dependencies.page_calculator
              @document_service_factory = dependencies.document_service_factory
              @config_reader = dependencies.config_reader
              @reader_state_reader = dependencies.reader_state_reader
              @state_writer = dependencies.state_writer
              @pagination_cache_preloader = dependencies.pagination_cache_preloader
              @runtime_config = dependencies.runtime_config
              @annotation_service = dependencies.annotation_service
              @selected_book_reader = dependencies.selected_book_reader
              @annotation_selection_reader = dependencies.annotation_selection_reader
              @annotation_view_refresher = dependencies.annotation_view_refresher
              @build_reader_controller = dependencies.build_reader_controller
              @file_probe = dependencies.file_probe
              @path_ops = dependencies.path_ops
              @process_control = dependencies.process_control

              @reader_launch_dependencies_factory = dependencies.reader_launch_dependencies_factory
              @reader_launch_service_factory = dependencies.reader_launch_service_factory
              @download_workflow_factory = dependencies.download_workflow_factory
              @dictionary_workflow_factory = dependencies.dictionary_workflow_factory
              @annotation_workflow_factory = dependencies.annotation_workflow_factory
              @progress_presenter_factory = dependencies.progress_presenter_factory

              @pagination_orchestrator = dependencies.pagination_orchestrator
              @clock = dependencies.clock
              @reader_session_context = dependencies.reader_session_context
              @menu_session_context = dependencies.menu_session_context
              document = dependencies.document
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
            # resilient-boundary
            rescue StandardError
              @logger&.debug('menu.state_controller.selected_book_read_failed')
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
            # resilient-boundary
            rescue StandardError
              @logger&.debug('menu.state_controller.annotation_selection_read_failed')
              [nil, nil]
            end

            def refresh_annotations_view
              return unless @annotation_view_refresher.respond_to?(:call)

              @annotation_view_refresher.call
            # resilient-boundary
            rescue StandardError
              @logger&.debug('menu.state_controller.annotations_view_refresh_failed')
              nil
            end

            def build_reader_launch_service
              deps = @reader_launch_dependencies_factory.call(
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
                path_ops: @path_ops,
                clock: @clock
              )
              @reader_launch_service_factory.call(deps)
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
                filtered_books_reader: -> { menu.filtered_epubs },
                logger: @logger
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
                clock: @clock,
                logger: @logger
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
                clock: @clock,
                logger: @logger
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
                mode_switcher: menu_mode_switcher_bridge,
                menu_state_reader: @menu_state_reader,
                menu_state_writer: @menu_state_writer,
                state_writer: @state_writer,
                annotation_service: @annotation_service,
                logger: @logger,
                selected_annotation_reader: annotation_selection_reader_bridge,
                annotations_view_refresher: annotation_view_refresh_bridge,
                reader_runner: reader_runner_bridge
              )
            end

            def menu_mode_switcher_bridge
              @menu_mode_switcher_bridge ||= MenuModeSwitcherBridge.new(menu: menu)
            end

            def annotation_selection_reader_bridge
              @annotation_selection_reader_bridge ||= AnnotationSelectionBridge.new(
                selected_annotation_reader: method(:read_selected_annotation_context),
                logger: @logger
              )
            end

            def annotation_view_refresh_bridge
              @annotation_view_refresh_bridge ||= AnnotationViewRefreshBridge.new(
                refresh_annotations_view: method(:refresh_annotations_view),
                logger: @logger
              )
            end

            def reader_runner_bridge
              @reader_runner_bridge ||= ReaderRunnerBridge.new(reader_runner: method(:run_reader))
            end

          end
        end
      end
    end
  end
end
