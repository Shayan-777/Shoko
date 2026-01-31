# frozen_string_literal: true

require 'fileutils'
require_relative '../mouseable_reader'
require_relative '../document_path_resolver'
require_relative '../../../core/services/pagination/pagination_orchestrator'
require_relative '../../main_menu/menu_progress_presenter'

module Shoko
  module Application::Controllers
    module Menu
      # Handles main-menu side effects such as launching books, refreshing scans,
      # and coordinating annotation mutations.
      class StateController
        include DocumentPathResolver

        def initialize(menu, pagination_cache: nil, display_capabilities: nil,
                       instrumentation: nil, download_service: nil,
                       dictionary_catalog_service: nil, logger: nil,
                       text_sanitizer: nil, background_worker_factory: nil,
                       recent_files_repository: nil, cache_pointer_resolver: nil,
                       dictionary_availability: nil, page_calculator: nil,
                       layout_service: nil, wrapping_service: nil,
                       document_service_factory: nil, config_reader: nil,
                       reader_state_reader: nil, state_writer: nil,
                       pagination_cache_preloader: nil, annotation_service: nil,
                       document: nil)
          @menu = menu
          @download_service_inst = download_service
          @dictionary_catalog_service_inst = dictionary_catalog_service
          @logger_inst = logger
          @text_sanitizer = text_sanitizer
          @background_worker_factory = background_worker_factory
          @recent_files_repository_inst = recent_files_repository
          @cache_pointer_resolver = cache_pointer_resolver
          @dictionary_availability = dictionary_availability
          @page_calculator_inst = page_calculator
          @layout_service = layout_service
          @wrapping_service = wrapping_service
          @document_service_factory = document_service_factory
          @config_reader = config_reader
          @reader_state_reader = reader_state_reader
          @state_writer = state_writer
          @pagination_cache_preloader = pagination_cache_preloader
          @annotation_service = annotation_service
          @document_inst = document
          @pagination_orchestrator = Core::Services::Pagination::PaginationOrchestrator.new(
            terminal_service: menu.terminal_service,
            pagination_cache: pagination_cache,
            frame_coordinator: menu.frame_coordinator,
            display_capabilities: display_capabilities,
            instrumentation: instrumentation
          )
        end

        def open_selected_book
          book = menu.selected_book
          book ||= begin
            idx = selectors.browse_selected(state)
            menu.filtered_epubs && menu.filtered_epubs[idx]
          end

          return unless book

          path = book['path']
          if path && File.exist?(path)
            load_and_open_with_progress(path)
          else
            catalog.scan_message = 'File not found'
            catalog.scan_status = :error
          end
        end

        def open_book(path)
          return file_not_found unless File.exist?(path)

          load_and_open_with_progress(path)
        rescue StandardError => e
          handle_reader_error(path, e)
        end

        def run_reader(path)
          prior_mode = selectors.mode(state)

          return unless ensure_reader_document_for(path)

          recent_path = canonical_recent_path(path)
          recent_files_repository&.add(recent_path) if recent_path

          # Debug: Log running flag dispatch from menu
          logger&.debug('menu.run_reader.dispatch_running', path: path, running: true)
          state.dispatch(action(:update_reader_meta, book_path: path, running: true))
          state.dispatch(action(:update_reader_mode, :read))

          # Debug: Verify running state after dispatch
          running_after = state.get(%i[reader running])
          logger&.debug('menu.run_reader.after_dispatch', running_value: running_after)

          Shoko::Application::ContainerFactory.build_reader_controller(dependencies, path).run
        rescue StandardError => e
          # Debug: Log any exception during reader execution
          logger&.error('menu.run_reader.exception', error: e.class.name, message: e.message)
          raise
        ensure
          logger&.debug('menu.run_reader.ensure', prior_mode: prior_mode)
          # Clear stale document from DI container so the next reader session
          # loads a fresh document rather than reusing the previous one.
          dependencies.unregister(:document)
          # Ensure terminal session depth is at least 1 (menu's session)
          # This guards against depth getting out of sync during reader exit
          terminal_service&.ensure_session_depth(1)
          menu.switch_to_mode(prior_mode || :browse)
        end

        def load_and_open_with_progress(path)
          return launch_without_overlay(path) if skip_progress_overlay?

          launch_with_overlay(path)
        end

        def file_not_found
          catalog.scan_message = 'File not found'
          catalog.scan_status = :error
        end

        def handle_reader_error(path, error)
          logger&.error('Failed to open book', error: error.message, path: path)
          catalog.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
          catalog.scan_status = :error

          return unless logger.respond_to?(:debug)

          logger&.debug('Reader error backtrace',
                        path: path,
                        backtrace: Array(error.backtrace).join("\n"))
        end

        def valid_cache_path?(path)
          return false unless path && File.file?(path)
          return false unless cache_pointer?(path)

          !!cache_payload(path, strict: true)
        rescue StandardError
          false
        end

        def refresh_scan(force: false)
          catalog.start_scan(force: force)
        end

        def search_downloads(query:, page_url: nil)
          service = download_service
          unless service
            update_download_state(download_status: :error, download_message: 'Download service unavailable')
            return
          end

          update_download_state(
            download_status: :searching,
            download_message: 'Searching Gutendex...',
            download_progress: 0.0,
            download_results: [],
            download_count: 0,
            download_next: nil,
            download_prev: nil,
            download_selected: 0
          )
          menu.draw_screen

          result = service.search(query: query, page_url: page_url)
          message = if result[:books].empty?
                      'No results'
                    else
                      "Found #{result[:books].length} of #{result[:count]}"
                    end
          update_download_state(
            download_results: result[:books],
            download_count: result[:count],
            download_next: result[:next],
            download_prev: result[:previous],
            download_selected: 0,
            download_status: :done,
            download_message: message,
            download_progress: 0.0
          )
        rescue StandardError => e
          update_download_state(download_status: :error,
                                download_message: "Search failed: #{e.message}",
                                download_progress: 0.0)
        ensure
          menu.draw_screen
        end

        def download_book(book)
          service = download_service
          unless service
            update_download_state(download_status: :error, download_message: 'Download service unavailable')
            menu.draw_screen
            return
          end

          title = safe_book_title(book)
          update_download_state(download_status: :downloading,
                                download_message: "Downloading #{title}...",
                                download_progress: 0.0)
          menu.draw_screen

          last_draw = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = service.download(book) do |done, total|
            progress = total.to_i.positive? ? done.to_f / total : 0.0
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            next if (now - last_draw) < 0.08 && progress < 1.0

            percent = total.to_i.positive? ? (progress * 100).round : nil
            message = percent ? "Downloading #{title}... #{percent}%" : "Downloading #{title}..."
            update_download_state(download_progress: progress, download_message: message)
            menu.draw_screen
            last_draw = now
          end

          downloaded_message = result[:existing] ? 'Already downloaded' : "Saved to #{File.basename(result[:path])}"
          update_download_state(download_status: :done,
                                download_message: downloaded_message,
                                download_progress: 0.0)
          refresh_scan(force: true)
        rescue StandardError => e
          update_download_state(download_status: :error,
                                download_message: "Download failed: #{e.message}",
                                download_progress: 0.0)
        ensure
          menu.draw_screen
        end

        def fetch_dictionary_catalog
          service = dictionary_catalog_service
          unless service
            update_dictionary_state(dictionary_status: :error, dictionary_message: 'Dictionary catalog unavailable')
            menu.draw_screen
            return
          end

          update_dictionary_state(dictionary_status: :loading,
                                  dictionary_message: 'Loading dictionary list...',
                                  dictionary_progress: 0.0,
                                  dictionary_results: [],
                                  dictionary_selected: 0)
          menu.draw_screen

          remote_items = service.list_remote
          results = merge_dictionary_installation(remote_items)
          update_dictionary_state(dictionary_status: :done,
                                  dictionary_message: "Found #{results.length} dictionaries",
                                  dictionary_progress: 0.0,
                                  dictionary_results: results,
                                  dictionary_selected: 0)
        rescue StandardError => e
          update_dictionary_state(dictionary_status: :error,
                                  dictionary_message: "Catalog failed: #{e.message}",
                                  dictionary_progress: 0.0)
        ensure
          menu.draw_screen
        end

        def download_dictionary(entry)
          return unless entry

          service = dictionary_catalog_service
          unless service
            update_dictionary_state(dictionary_status: :error, dictionary_message: 'Dictionary catalog unavailable')
            menu.draw_screen
            return
          end

          name = entry[:name] || entry['name'] || 'dictionary'
          update_dictionary_state(dictionary_status: :downloading,
                                  dictionary_message: "Downloading #{name}...",
                                  dictionary_progress: 0.0)
          menu.draw_screen

          last_draw = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          dest_dir = dictionary_storage_path
          result = service.download(entry, dest_dir) do |done, total|
            progress = total.to_i.positive? ? done.to_f / total : 0.0
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            next if (now - last_draw) < 0.08 && progress < 1.0

            percent = total.to_i.positive? ? (progress * 100).round : nil
            message = percent ? "Downloading #{name}... #{percent}%" : "Downloading #{name}..."
            update_dictionary_state(dictionary_progress: progress, dictionary_message: message)
            menu.draw_screen
            last_draw = now
          end

          message = result[:existing] ? 'Already installed' : "Saved to #{File.basename(result[:path])}"
          update_dictionary_state(dictionary_status: :done,
                                  dictionary_message: message,
                                  dictionary_progress: 0.0)
          mark_dictionary_installed(result[:path]) if result[:path]
        rescue StandardError => e
          update_dictionary_state(dictionary_status: :error,
                                  dictionary_message: "Download failed: #{e.message}",
                                  dictionary_progress: 0.0)
        ensure
          menu.draw_screen
        end

        def open_selected_annotation
          annotation_actions.open_selected_annotation
        end

        def open_selected_annotation_for_edit
          annotation_actions.open_selected_annotation_for_edit
        end

        def delete_selected_annotation
          annotation_actions.delete_selected_annotation
        end

        def save_current_annotation_edit
          annotation_actions.save_current_annotation_edit
        end

        private

        attr_reader :menu

        def annotation_service_ref
          @annotation_service
        end

        def state
          menu.state
        end

        def dependencies
          menu.container
        end

        def catalog
          menu.catalog
        end

        def terminal_service
          menu.terminal_service
        end

        def selectors
          Shoko::Application::Selectors::MenuSelectors
        end

        def action(type, payload = nil)
          case type
          when :update_reader_meta
            Shoko::Application::Actions::UpdateReaderMetaAction.new(**(payload || {}))
          when :update_reader_mode
            Shoko::Application::Actions::UpdateReaderAction.new(mode: payload)
          when :update_menu
            Shoko::Application::Actions::UpdateMenuAction.new(**(payload || {}))
          else
            raise ArgumentError, "Unknown action #{type}"
          end
        end

        def progress_presenter
          @progress_presenter ||= Application::MainMenu::MenuProgressPresenter.new(state)
        end

        def download_service
          @download_service_inst
        end

        def dictionary_catalog_service
          @dictionary_catalog_service_inst
        end

        def logger
          @logger_inst
        end

        def update_download_state(payload)
          state.dispatch(action(:update_menu, payload))
        end

        def update_dictionary_state(payload)
          state.dispatch(action(:update_menu, payload))
        end

        def dictionary_storage_path
          dict_avail = @dictionary_availability
          config_path = state.get(%i[config dictionary_path]).to_s.strip
          path = if config_path.empty?
                   dict_avail&.default_databases_path || File.join(Dir.home, '.local', 'share', 'shoko', 'dictionaries')
                 else
                   File.expand_path(config_path)
                 end
          FileUtils.mkdir_p(path)
          path
        rescue StandardError
          fallback = dict_avail&.default_databases_path || File.join(Dir.home, '.local', 'share', 'shoko',
                                                                     'dictionaries')
          FileUtils.mkdir_p(fallback)
          fallback
        end

        def merge_dictionary_installation(remote_items)
          base_path = dictionary_storage_path
          Array(remote_items).filter_map do |item|
            name = item[:name] || item['name']
            next unless name

            path = File.join(base_path, name.to_s)
            installed = File.exist?(path)
            item.merge(installed: installed, path: path)
          end
        end

        def mark_dictionary_installed(path)
          results = Array(state.get(%i[menu dictionary_results]))
          return if results.empty?

          updated = results.map do |item|
            next item unless item[:path].to_s == path.to_s

            item.merge(installed: true)
          end
          update_dictionary_state(dictionary_results: updated)
        end

        def safe_book_title(book)
          return 'book' unless book.respond_to?(:[])

          title = book[:title] || book['title'] || 'book'
          if @text_sanitizer
            @text_sanitizer.sanitize(title.to_s, preserve_newlines: false, max_length: nil)
          else
            title.to_s
          end
        end

        def build_background_worker(name:)
          factory = @background_worker_factory
          return nil unless factory.respond_to?(:call)

          factory.call(name:)
        rescue StandardError
          nil
        end

        def canonical_recent_path(path)
          resolve_source_path(path)
        end

        def recent_files_repository
          @recent_files_repository_inst
        end

        def cache_pointer?(path)
          @cache_pointer_resolver ? @cache_pointer_resolver.cache_pointer?(path) : false
        end

        def cache_payload(path, strict:)
          @cache_pointer_resolver&.read_cache(path, strict: strict)
        end

        def prepare_reader_launch(path, presenter)
          height, width = terminal_service.size
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
          # Touch services to ensure they're initialized (no-op if already set)
          page_calculator
          ensure_background_worker
        end

        def load_document_for(path, progress_reporter: nil)
          raise 'document_service_factory not available' unless @document_service_factory

          @document_service_factory.call(path, progress_reporter: progress_reporter).load_document
        end

        def ensure_reader_document_for(path)
          target_path = canonical_reader_path(path)
          existing = @document_inst
          return true if document_matches_path?(existing, target_path)

          document = load_document_for(path)
          register_document(document)
          update_total_chapters(document)
          true
        rescue StandardError => e
          handle_reader_error(path, e)
          false
        end

        def document_cached?(document)
          document.respond_to?(:cached?) && document.cached?
        end

        def register_document(document)
          dependencies.register(:document, document)
        end

        def update_total_chapters(document)
          total = document&.chapter_count || 0
          state.dispatch(Shoko::Application::Actions::UpdatePaginationStateAction.new(total_chapters: total))
        end

        def ensure_background_worker
          return if dependencies.respond_to?(:registered?) && dependencies.registered?(:background_worker)

          worker = build_background_worker(name: 'document-preload')
          dependencies.register(:background_worker, worker) if worker
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
            menu.draw_screen
          end

          session.build_full_map! do |done, total|
            presenter.update(done: done, total: total)
            menu.draw_screen
          end
          presenter.update(done: 1, total: 1)
        end

        def progress_reporter_for(presenter)
          return nil unless presenter.respond_to?(:update_status)

          last_update = nil
          lambda do |message: nil, progress: nil|
            changed = presenter.update_status(message: message, progress: progress)
            return unless changed

            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if last_update.nil? || (now - last_update) >= 0.05
              menu.draw_screen
              last_update = now
            end
          end
        end

        def skip_progress_overlay?
          primary = ENV.fetch('SHOKO_SKIP_PROGRESS_OVERLAY', '').to_s.strip
          primary == '1'
        end

        def annotation_actions
          @annotation_actions ||= AnnotationActions.new(self)
        end

        def page_calculator
          @page_calculator_inst
        end

        def preload_cached_pagination(document, width, height)
          preloader = @pagination_cache_preloader
          return unless preloader

          preloader.preload(document, width:, height:)
        rescue StandardError => e
          begin
            logger&.debug('StateController: cached pagination preload failed',
                          error: e.message, path: @path)
          rescue StandardError
            nil
          end
          nil
        end

        def launch_without_overlay(path)
          warm_launch_dependencies
          target_path = prepare_reader_launch(path, null_presenter)
          run_reader(target_path || path)
        rescue StandardError => e
          handle_reader_error(path, e)
        end

        def launch_with_overlay(path)
          index = selectors.browse_selected(state) || 0
          mode = selectors.mode(state)
          presenter = progress_presenter
          presenter.show(path: path, index: index, mode: mode)

          target_path = nil
          begin
            target_path = prepare_reader_launch(path, presenter)
          ensure
            presenter.clear
          end

          run_reader(target_path || path)
        end

        def null_presenter
          @null_presenter ||= NullProgressPresenter.new
        end
      end
    end
  end
end

module Shoko
  module Application::Controllers
    module Menu
      # Collection of annotation-related behaviours factored out of StateController.
      class AnnotationActions
        def initialize(controller)
          @controller = controller
        end

        def open_selected_annotation
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          normalized = normalize_annotation(annotation)
          state.dispatch(Shoko::Application::Actions::UpdateReaderMetaAction.new(book_path: book_path))
          pending_payload = {
            chapter_index: normalized[:chapter_index],
            selection_range: normalized[:range],
            annotation: annotation,
            edit: false,
          }
          state.dispatch(Shoko::Application::Actions::UpdateSelectionsAction.new(pending_jump: pending_payload))

          controller.run_reader(book_path)
        end

        def open_selected_annotation_for_edit
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          note_text = annotation[:note] || annotation['note'] || ''
          state.dispatch(action(:update_menu,
                                selected_annotation: annotation,
                                selected_annotation_book: book_path,
                                annotation_edit_text: note_text,
                                annotation_edit_cursor: note_text.length))
          menu.switch_to_mode(:annotation_editor)
        end

        def delete_selected_annotation
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          ann_id = annotation[:id] || annotation['id']
          return unless ann_id

          service = controller.send(:annotation_service_ref)
          begin
            service&.delete(book_path, ann_id)
            state.dispatch(action(:update_menu, annotations_all: service&.list_all || {}))
          rescue StandardError => e
            logger&.error('Failed to delete annotation', error: e.message, path: book_path)
          end

          menu.annotations_screen.refresh_data
        end

        def save_current_annotation_edit
          context = current_annotation_edit_context
          return unless context

          with_annotation_service do |service|
            service.update(context[:path], context[:id], context[:text])
            state.dispatch(action(:update_menu, annotations_all: service.list_all))
          end

          menu.switch_to_mode(:annotations)
          menu.annotations_screen.refresh_data
        end

        private

        attr_reader :controller

        def menu
          controller.send(:menu)
        end

        def state
          controller.send(:state)
        end

        def action(type, payload = nil)
          controller.send(:action, type, payload)
        end

        def logger
          controller.send(:logger)
        end

        def selected_annotation_and_path
          screen = menu.annotations_screen
          [screen.current_annotation, screen.current_book_path]
        end

        def normalize_annotation(annotation)
          return {} unless annotation.is_a?(Hash)

          annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
        end

        def current_annotation_edit_context
          annotation = state.get(%i[menu selected_annotation]) || {}
          path = state.get(%i[menu selected_annotation_book])
          text = state.get(%i[menu annotation_edit_text]) || ''
          return unless path && annotation

          ann_id = annotation[:id] || annotation['id']
          return unless ann_id

          { path: path, id: ann_id, text: text }
        end

        def with_annotation_service
          service = controller.send(:annotation_service_ref)
          return unless service

          yield(service)
        rescue StandardError => e
          logger&.error('Annotation service failure', error: e.message)
        end
      end

      # No-op progress presenter used when the overlay is skipped.
      class NullProgressPresenter
        def show(*) end

        def update(*) end

        def update_status(*) end

        def update_message(*) end

        def set_progress(*) end

        def clear(*) end
      end
    end
  end
end
