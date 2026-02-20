# frozen_string_literal: true

require_relative '../dependencies/menu_controller_dependencies'

require_relative 'state_controller'
require_relative 'input_controller'
require_relative 'actions/lifecycle_actions'
require_relative 'actions/navigation_actions'
require_relative 'actions/download_actions'
require_relative 'actions/dictionary_actions'
require_relative 'actions/settings_actions'

module Shoko
  module Adapters::Input::Controllers
    module Menu
      # Controller responsible for the menu orchestration loop.
      class Controller
        include Actions::Lifecycle
        include Actions::Navigation
        include Actions::Download
        include Actions::Dictionary
        include Actions::Settings

        attr_accessor :filtered_epubs
        attr_reader :observer_registry, :main_menu_component, :catalog,
                    :terminal_service, :frame_coordinator, :render_pipeline,
                    :state_controller, :input_controller, :menu_state_reader, :menu_state_writer,
                    :command_bus

        def initialize(deps:)
          deps.validate!

          @observer_registry = deps.observer_registry
          @catalog = deps.catalog
          @terminal_service = deps.terminal_service
          @frame_coordinator = deps.frame_coordinator
          @render_pipeline = deps.render_pipeline
          @main_menu_component = deps.ui_component_factory.main_menu_component(
            controller: self,
            menu_ui_dependencies: deps.menu_ui_dependencies
          )
          @filtered_epubs = []
          @notification_service = deps.notification_service
          @settings_service_ref = deps.settings_service
          @annotation_service_ref = deps.annotation_service
          @logger_ref = deps.logger
          @menu_state_reader = deps.menu_state_reader
          @menu_state_writer = deps.menu_state_writer
          @command_bus = deps.command_bus
          @file_probe = deps.file_probe
          @path_ops = deps.path_ops
          @clock = deps.clock
          @process_control = deps.process_control

          @state_controller = StateController.new(
            self,
            pagination_orchestrator: deps.pagination_orchestrator,
            download_service: deps.download_service,
            dictionary_catalog_service: deps.dictionary_catalog_service,
            logger: deps.logger,
            text_sanitizer: deps.text_sanitizer,
            background_worker_factory: deps.background_worker_factory,
            recent_files_repository: deps.recent_files_repository,
            cache_pointer_resolver: deps.cache_pointer_resolver,
            dictionary_availability: deps.dictionary_availability,
            dictionary_storage: deps.dictionary_storage,
            page_calculator: deps.page_calculator,
            layout_service: deps.layout_service,
            wrapping_service: deps.wrapping_service,
            document_service_factory: deps.document_service_factory,
            config_reader: deps.config_reader,
            reader_state_reader: deps.reader_state_reader,
            state_writer: deps.state_writer,
            pagination_cache_preloader: deps.pagination_cache_preloader,
            runtime_config: deps.runtime_config,
            reader_session_context: deps.reader_session_context,
            menu_session_context: deps.menu_session_context,
            annotation_service: deps.annotation_service,
            selected_book_reader: method(:selected_browse_book),
            annotation_selection_reader: method(:selected_annotation_context),
            annotation_view_refresher: method(:refresh_annotations_screen),
            build_reader_controller: deps.build_reader_controller,
            document: deps.document,
            menu_state_reader: deps.menu_state_reader,
            menu_state_writer: deps.menu_state_writer,
            file_probe: deps.file_probe,
            path_ops: deps.path_ops,
            clock: deps.clock,
            process_control: deps.process_control
          )
          @input_controller = InputController.new(
            self,
            key_classifier: deps.key_classifier,
            input_system_factory: deps.input_system_factory
          )
          @dispatcher = @input_controller.dispatcher
        end

        private

        attr_reader :notification_service

        def logger
          @logger_ref
        end

        def settings_service
          @settings_service_ref
        end

        def preload_annotations
          return @menu_state_writer.update_menu(annotations_all: {}) unless @annotation_service_ref

          @menu_state_writer.update_menu(annotations_all: @annotation_service_ref.list_all)
        rescue StandardError
          @menu_state_writer.update_menu(annotations_all: {})
        end

        def reset_download_state
          @menu_state_writer.update_menu(
            download_query: '',
            download_cursor: 0,
            download_selected: 0,
            download_results: [],
            download_count: 0,
            download_next: nil,
            download_prev: nil,
            download_status: :idle,
            download_message: '',
            download_progress: 0.0
          )
        end

        def reset_dictionary_state
          @menu_state_writer.update_menu(
            dictionary_selected: 0,
            dictionary_query: '',
            dictionary_cursor: 0,
            dictionary_results: [],
            dictionary_status: :idle,
            dictionary_message: '',
            dictionary_progress: 0.0
          )
        end

        def update_download_selection(delta)
          results = Array(@menu_state_reader.download_results)
          max_index = [results.length - 1, 0].max
          current = (@menu_state_reader.download_selected || 0).to_i
          new_val = (current + delta).clamp(0, max_index)
          @menu_state_writer.update_menu(download_selected: new_val)
        end

        def selected_download_book
          results = Array(@menu_state_reader.download_results)
          index = (@menu_state_reader.download_selected || 0).to_i
          results[index]
        end

        def selected_library_item
          screen = main_menu_component&.current_screen
          items = screen.respond_to?(:items) ? screen.items : []
          index = @menu_state_reader.browse_selected || 0
          items[index]
        end

        def selected_browse_book
          index = (@menu_state_reader.browse_selected || 0).to_i
          screen = main_menu_component&.browse_screen
          if screen.respond_to?(:book_at)
            screen.book_at(index)
          else
            Array(@filtered_epubs)[index]
          end
        end

        def selected_annotation_context
          screen = @main_menu_component.annotations_screen
          {
            annotation: screen.current_annotation,
            book_path: screen.current_book_path
          }
        end

        def refresh_annotations_screen
          @main_menu_component.annotations_screen.refresh_data
        end

        def resolve_library_path(item)
          primary = item.respond_to?(:open_path) ? item.open_path : nil
          return primary if state_controller.valid_cache_path?(primary)

          fallback = item.respond_to?(:epub_path) ? item.epub_path : nil
          return fallback if fallback && !fallback.empty? && file_exists?(fallback)

          nil
        end

        def file_exists?(path)
          @file_probe&.exist?(path)
        end
      end
    end
  end
end
