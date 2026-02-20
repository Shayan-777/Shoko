# frozen_string_literal: true

module Shoko
  module Adapters::Input::Controllers
    module Menu
      # Coordinates menu workflows while keeping all heavy logic in dedicated services.
      class StateController
        class NullWorkflow
          def search_downloads(**); end
          def download_book(_book); end
          def fetch_dictionary_catalog; end
          def download_dictionary(_entry); end
          def open_selected_annotation; end
          def open_selected_annotation_for_edit; end
          def delete_selected_annotation; end
          def save_current_annotation_edit; end
        end

        class NullProgressPresenter
          def show(**); end
          def update(**); end
          def update_message(_message); end
          def set_progress(_progress); end
          def update_status(message: nil, progress: nil)
            !message.nil? || !progress.nil?
          end
          def clear; end
        end

        class LegacyReaderLaunchService
          def initialize(reader_session_context:, document_service_factory:, state_writer:,
                         cache_pointer_resolver: nil, file_probe: nil, path_ops: nil, logger: nil)
            @reader_session_context = reader_session_context
            @document_service_factory = document_service_factory
            @state_writer = state_writer
            @cache_pointer_resolver = cache_pointer_resolver
            @file_probe = file_probe
            @path_ops = path_ops
            @logger = logger
          end

          def open_selected_book; end

          def open_book(path)
            ensure_reader_document_for(path)
          end

          def run_reader(path)
            ensure_reader_document_for(path)
          end

          def load_and_open_with_progress(path)
            ensure_reader_document_for(path)
          end

          def file_not_found; end

          def handle_reader_error(_path, _error); end

          def valid_cache_path?(path)
            return false unless path && file_regular?(path)
            return false unless cache_pointer?(path)

            !!cache_payload(path, strict: true)
          rescue StandardError
            false
          end

          def ensure_reader_document_for(path)
            target_path = canonical_reader_path(path) || path
            existing = @reader_session_context&.document
            return true if document_matches_path?(existing, target_path)

            document = load_document_for(target_path)
            @reader_session_context.document = document if @reader_session_context
            @state_writer&.update_pagination_state(total_chapters: document&.chapter_count || 0)
            true
          rescue StandardError => e
            @logger&.error('menu.reader_launch_fallback.ensure_reader_document_for_failed',
                           error: e.class.name, message: e.message, path: path)
            false
          end

          private

          def load_document_for(path)
            raise 'document_service_factory not available' unless @document_service_factory

            @document_service_factory.call(path, progress_reporter: nil, background_worker: nil).load_document
          end

          def canonical_reader_path(path)
            return nil unless path

            source = resolve_source_path(path)
            safe_expand_path(source)
          rescue StandardError
            path
          end

          def resolve_source_path(path)
            resolver = @cache_pointer_resolver
            return path unless resolver&.cache_pointer?(path)

            payload = resolver.read_cache(path, strict: false)
            source = payload&.source_path
            source && !source.empty? ? source : path
          rescue StandardError
            path
          end

          def document_matches_path?(document, target_path)
            return false unless document && target_path

            doc_path = if document.respond_to?(:canonical_path)
                         document.canonical_path
                       elsif document.respond_to?(:source_path)
                         document.source_path
                       elsif document.respond_to?(:path)
                         document.path
                       end
            return false unless doc_path

            safe_expand_path(doc_path) == safe_expand_path(target_path)
          rescue StandardError
            false
          end

          def safe_expand_path(path)
            return path.to_s unless @path_ops&.respond_to?(:expand_path)

            @path_ops.expand_path(path).to_s
          rescue StandardError
            path.to_s
          end

          def cache_pointer?(path)
            @cache_pointer_resolver ? @cache_pointer_resolver.cache_pointer?(path) : false
          end

          def cache_payload(path, strict:)
            @cache_pointer_resolver&.read_cache(path, strict: strict)
          end

          def file_regular?(path)
            return @file_probe.regular?(path) if @file_probe&.respond_to?(:regular?)

            File.file?(path)
          rescue StandardError
            false
          end
        end

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

        # Backward-compatible private helper used by existing specs.
        def ensure_reader_document_for(path)
          @reader_launch_service.ensure_reader_document_for(path)
        end

        def catalog
          menu.catalog
        end

        def progress_presenter
          @progress_presenter ||= if @progress_presenter_factory.respond_to?(:call)
                                    @progress_presenter_factory.call
                                  else
                                    NullProgressPresenter.new
                                  end
        rescue StandardError
          NullProgressPresenter.new
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
          if @reader_launch_service_factory.respond_to?(:call)
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
          else
            LegacyReaderLaunchService.new(
              reader_session_context: @reader_session_context,
              document_service_factory: @document_service_factory,
              state_writer: @state_writer,
              cache_pointer_resolver: @cache_pointer_resolver,
              file_probe: @file_probe,
              path_ops: @path_ops,
              logger: @logger
            )
          end
        end

        def build_download_workflow
          return NullWorkflow.new unless @download_workflow_factory.respond_to?(:call)

          @download_workflow_factory.call(
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
          return NullWorkflow.new unless @dictionary_workflow_factory.respond_to?(:call)

          @dictionary_workflow_factory.call(
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
          return NullWorkflow.new unless @annotation_workflow_factory.respond_to?(:call)

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
      end
    end
  end
end
