# frozen_string_literal: true

require_relative 'mouseable_reader'
require_relative '../main_menu/menu_progress_presenter'
require_relative '../composition/dependencies/menu_controller_dependencies'
require_relative 'menu/state_controller'
require_relative 'menu/input_controller'

module Shoko
  module Application::Controllers
    # Controller responsible for the menu orchestration loop.
    class MenuController
      attr_accessor :filtered_epubs
      attr_reader :state, :main_menu_component, :catalog,
                  :terminal_service, :frame_coordinator, :render_pipeline,
                  :state_controller, :input_controller, :menu_state_reader,
                  :command_port

      def initialize(deps: nil, **legacy_kwargs)
        deps ||= Shoko::Application::Composition::Dependencies::MenuControllerDependencies.build(**legacy_kwargs)

        @state = deps.state
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
        @command_port = deps.command_port
        @file_probe = deps.file_probe
        @path_ops = deps.path_ops
        @clock = deps.clock
        @process_control = deps.process_control

        @state_controller = Menu::StateController.new(
          self,
          pagination_cache: deps.pagination_cache,
          display_capabilities: deps.display_capabilities,
          instrumentation: deps.instrumentation,
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
        @input_controller = Menu::InputController.new(
          self,
          key_classifier: deps.key_classifier,
          input_system_factory: deps.input_system_factory
        )
        @dispatcher = @input_controller.dispatcher
      end

      def run
        @terminal_service.setup
        @catalog.load_cached
        epubs = @catalog.entries || []
        @filtered_epubs = epubs
        @main_menu_component.browse_screen.filtered_epubs = epubs
        @catalog.start_scan if epubs.empty?

        main_loop
      rescue Interrupt
        cleanup_and_exit(0, "\nGoodbye!")
      rescue StandardError => e
        cleanup_and_exit(1, "Error: #{e.message}", e)
      ensure
        begin
          if @terminal_service.respond_to?(:force_cleanup)
            @terminal_service.force_cleanup
          elsif @terminal_service.respond_to?(:cleanup)
            @terminal_service.cleanup
          end
        rescue StandardError
          # best effort; leave terminal as-is if cleanup fails here
        end
        @catalog.cleanup if @catalog.respond_to?(:cleanup)
      end

      def handle_menu_selection
        case @menu_state_reader.selected
        when 0 then switch_to_browse
        when 1 then switch_to_mode(:library)
        when 2 then switch_to_mode(:annotations)
        when 3 then open_download_screen
        when 4 then switch_to_mode(:settings)
        when 5 then cleanup_and_exit(0, '')
        end
      end

      def handle_navigation(direction)
        current = @menu_state_reader.selected
        max_val = 5

        new_selected = case direction
                       when :up then [current - 1, 0].max
                       when :down then [current + 1, max_val].min
                       else current
                       end
        @menu_state_writer.update_menu(selected: new_selected)
      end

      def switch_to_browse
        @menu_state_writer.update_menu(mode: :browse, search_active: false)
        input_controller.activate(@menu_state_reader.mode)
      end

      def switch_to_search
        @menu_state_writer.update_menu(mode: :search, search_active: true)
        input_controller.activate(@menu_state_reader.mode)
      end

      def switch_to_mode(mode)
        payload = { mode: mode, browse_selected: 0 }
        payload[:settings_selected] = 1 if mode == :settings
        @menu_state_writer.update_menu(payload)
        preload_annotations if mode == :annotations
        input_controller.activate(@menu_state_reader.mode)
      end

      def open_download_screen
        reset_download_state
        @menu_state_writer.update_menu(mode: :download)
        input_controller.activate(@menu_state_reader.mode)
      end

      def download_start_search
        query = @menu_state_reader.download_query.to_s
        @menu_state_writer.update_menu(mode: :download_search, download_cursor: query.length)
        input_controller.activate(@menu_state_reader.mode)
      end

      def download_exit_search
        @menu_state_writer.update_menu(mode: :download)
        input_controller.activate(@menu_state_reader.mode)
      end

      def download_submit_search
        query = @menu_state_reader.download_query.to_s
        state_controller.search_downloads(query: query)
        download_exit_search
      end

      def download_refresh
        query = @menu_state_reader.download_query.to_s
        state_controller.search_downloads(query: query)
      end

      def download_next_page
        next_url = @menu_state_reader.download_next
        return unless next_url

        query = @menu_state_reader.download_query.to_s
        state_controller.search_downloads(query: query, page_url: next_url)
      end

      def download_prev_page
        prev_url = @menu_state_reader.download_prev
        return unless prev_url

        query = @menu_state_reader.download_query.to_s
        state_controller.search_downloads(query: query, page_url: prev_url)
      end

      def download_up
        update_download_selection(-1)
      end

      def download_down
        update_download_selection(1)
      end

      def download_confirm
        book = selected_download_book
        return unless book

        state_controller.download_book(book)
      end

      def cleanup_and_exit(code, message, error = nil)
        cleanup_terminal

        log_exit(message, error)
        @process_control&.terminate(code)
      end

      def refresh_scan(force: true)
        state_controller.refresh_scan(force: force)
      end

      # Settings are handled directly via dispatcher bindings
      def toggle_view_mode(_key = nil)
        settings_service.toggle_view_mode
      end

      def toggle_page_numbers(_key = nil)
        settings_service.toggle_page_numbers
      end

      def cycle_line_spacing(_key = nil)
        settings_service.cycle_line_spacing
      end

      def toggle_highlight_quotes(_key = nil)
        settings_service.toggle_highlight_quotes
      end

      def toggle_dictionary_backend(_key = nil)
        settings_service.toggle_dictionary_backend
      end

      def cycle_dictionary_pair(_key = nil)
        settings_service.cycle_dictionary_pair
      end

      def open_dictionary_settings(_key = nil)
        reset_dictionary_state
        @menu_state_writer.update_menu(mode: :dictionary, dictionary_selected: 0)
        input_controller.activate(:dictionary)
        state_controller.fetch_dictionary_catalog
      end

      def toggle_kitty_images(_key = nil)
        settings_service.toggle_kitty_images
      end

      def toggle_page_numbering_mode(_key = nil)
        settings_service.toggle_page_numbering_mode
      end

      def wipe_cache(_key = nil)
        message = settings_service.wipe_cache(
          catalog: @catalog,
          cached: @menu_state_reader.wipe_cache_cached? || nil,
          downloads: @menu_state_reader.wipe_cache_downloads? || nil,
          nuke: @menu_state_reader.wipe_cache_nuke? || nil,
          annotations: @menu_state_reader.wipe_cache_annotations? || nil,
          bookmarks: @menu_state_reader.wipe_cache_bookmarks? || nil,
          progress: @menu_state_reader.wipe_cache_progress? || nil,
          config_file: @menu_state_reader.wipe_cache_config? || nil
        )
        @filtered_epubs = []
        @catalog.scan_message = message if @catalog.respond_to?(:scan_message)
        message
      end

      def toggle_wipe_cache_cached(_key = nil)
        toggle_wipe_cache_flag(:wipe_cache_cached, default: true)
      end

      def toggle_wipe_cache_downloads(_key = nil)
        toggle_wipe_cache_flag(:wipe_cache_downloads, default: false)
      end

      def toggle_wipe_cache_annotations(_key = nil)
        toggle_wipe_cache_flag(:wipe_cache_annotations, default: false)
      end

      def toggle_wipe_cache_bookmarks(_key = nil)
        toggle_wipe_cache_flag(:wipe_cache_bookmarks, default: false)
      end

      def toggle_wipe_cache_progress(_key = nil)
        toggle_wipe_cache_flag(:wipe_cache_progress, default: false)
      end

      def toggle_wipe_cache_config(_key = nil)
        toggle_wipe_cache_flag(:wipe_cache_config, default: false)
      end

      def toggle_wipe_cache_nuke(_key = nil)
        current = @menu_state_reader.wipe_cache_nuke?
        new_value = !current

        payload = { wipe_cache_nuke: new_value }
        if new_value
          payload[:wipe_cache_cached] = true
          payload[:wipe_cache_downloads] = true
          payload[:wipe_cache_annotations] = true
          payload[:wipe_cache_bookmarks] = true
          payload[:wipe_cache_progress] = true
          payload[:wipe_cache_config] = true
        end

        @menu_state_writer.update_menu(payload)
      end

      def dictionary_up
        update_dictionary_selection(-1)
      end

      def dictionary_down
        update_dictionary_selection(1)
      end

      def dictionary_select
        index = (@menu_state_reader.dictionary_selected || 0).to_i
        action_count = dictionary_action_count

        if index < action_count
          handle_dictionary_action(index)
        else
          entry = selected_dictionary_entry
          state_controller.download_dictionary(entry) if entry
        end
      end

      def dictionary_start_search
        query = @menu_state_reader.dictionary_query.to_s
        @menu_state_writer.update_menu(mode: :dictionary_search, dictionary_cursor: query.length)
        input_controller.activate(:dictionary_search)
      end

      def dictionary_back
        @menu_state_writer.update_menu(mode: :settings)
        input_controller.activate(:settings)
      end

      def dictionary_exit_search
        @menu_state_writer.update_menu(mode: :dictionary)
        input_controller.activate(:dictionary)
      end

      def dictionary_submit_search
        @menu_state_writer.update_menu(mode: :dictionary, dictionary_selected: 0)
        input_controller.activate(:dictionary)
      end

      def toggle_wipe_cache_flag(key, default:)
        current = read_wipe_cache_flag(key, default: default)
        new_val = !current

        payload = { key => new_val }
        payload[:wipe_cache_nuke] = false if !new_val && @menu_state_reader.wipe_cache_nuke?

        @menu_state_writer.update_menu(payload)
      end

      def read_wipe_cache_flag(key, default:)
        case key
        when :wipe_cache_cached then @menu_state_reader.wipe_cache_cached?
        when :wipe_cache_downloads then @menu_state_reader.wipe_cache_downloads?
        when :wipe_cache_annotations then @menu_state_reader.wipe_cache_annotations?
        when :wipe_cache_bookmarks then @menu_state_reader.wipe_cache_bookmarks?
        when :wipe_cache_progress then @menu_state_reader.wipe_cache_progress?
        when :wipe_cache_config then @menu_state_reader.wipe_cache_config?
        else default
        end
      end

      def dictionary_refresh
        state_controller.fetch_dictionary_catalog
      end

      # Library mode helpers
      def library_up
        current = @menu_state_reader.browse_selected || 0
        @menu_state_writer.update_menu(browse_selected: (current - 1).clamp(0, current))
      end

      def library_down
        items = if main_menu_component&.current_screen.respond_to?(:items)
                  main_menu_component.current_screen.items
                else
                  []
                end
        max_index = [items.length - 1, 0].max
        current = @menu_state_reader.browse_selected || 0
        @menu_state_writer.update_menu(browse_selected: (current + 1).clamp(0, max_index))
      end

      def library_select
        item = selected_library_item
        return unless item

        target_path = resolve_library_path(item)
        return state_controller.file_not_found unless target_path

        state_controller.run_reader(target_path)
      end

      def open_selected_book
        state_controller.open_selected_book
      end

      def main_loop
        draw_screen
        loop do
          process_scan_results_if_available
          handle_user_input
          draw_screen
        end
      end

      def handle_user_input
        keys = read_input_keys(timeout: annotation_editor_active? ? blink_poll_interval : nil)
        input_controller.handle_keys(keys)
      end

      def read_input_keys(timeout: nil)
        @terminal_service.read_keys_blocking(limit: 10, timeout: timeout)
      end

      def process_scan_results_if_available
        return unless (epubs = @catalog.process_results)

        @filtered_epubs = epubs
        @main_menu_component.browse_screen.filtered_epubs = epubs
        @main_menu_component.library_screen.invalidate_cache!
      end

      def draw_screen
        notification_service&.tick
        @frame_coordinator.with_frame do |surface, bounds, _w, _h|
          @render_pipeline.render_component(surface, bounds, @main_menu_component)
        end
      end

      def annotation_editor_active?
        @menu_state_reader.mode == :annotation_editor
      rescue StandardError
        false
      end

      def blink_poll_interval
        0.1
      end

      # Annotation helpers (public so dispatcher can invoke explicitly)
      def open_selected_annotation
        state_controller.open_selected_annotation
      end

      def open_selected_annotation_for_edit
        state_controller.open_selected_annotation_for_edit
      end

      def delete_selected_annotation
        state_controller.delete_selected_annotation
      end

      def save_current_annotation_edit
        state_controller.save_current_annotation_edit
      end

      private

      # Provide current editor component for application commands in menu context
      def current_editor_component
        return nil unless @menu_state_reader.mode == :annotation_editor

        @main_menu_component&.annotation_edit_screen
      end

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

      def update_dictionary_selection(delta)
        max_index = [dictionary_item_count - 1, 0].max
        current = (@menu_state_reader.dictionary_selected || 0).to_i
        new_val = (current + delta).clamp(0, max_index)
        @menu_state_writer.update_menu(dictionary_selected: new_val)
      end

      def dictionary_item_count
        dictionary_action_count + dictionary_filtered_results.length
      end

      def dictionary_action_count
        5
      end

      def dictionary_filtered_results
        query = @menu_state_reader.dictionary_query.to_s.downcase
        results = Array(@menu_state_reader.dictionary_results)
        return results if query.empty?

        results.select do |item|
          name = item[:name].to_s.downcase
          pair = "#{item[:source]}-#{item[:target]}".downcase
          name.include?(query) || pair.include?(query)
        end
      end

      def selected_dictionary_entry
        index = (@menu_state_reader.dictionary_selected || 0).to_i
        list_index = index - dictionary_action_count
        return nil if list_index.negative?

        dictionary_filtered_results[list_index]
      end

      def handle_dictionary_action(index)
        case index
        when 0
          dictionary_back
        when 1
          toggle_dictionary_backend
        when 2
          cycle_dictionary_pair
        when 3
          # Storage path row (no action)
          nil
        when 4
          dictionary_refresh
        end
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

      def cleanup_terminal
        terminal = terminal_service
        return unless terminal

        cleanup_error = nil
        begin
          terminal.cleanup
        rescue StandardError => e
          cleanup_error = e
          @logger_ref&.error('Menu terminal cleanup failed', error: e.message)
        ensure
          force_cleanup_if_needed(terminal, cleanup_error)
        end
      end

      def force_cleanup_if_needed(terminal, cleanup_error)
        return unless terminal.respond_to?(:force_cleanup)

        remaining_depth = terminal.session_depth || 0
        needs_force = cleanup_error || remaining_depth.positive?
        return unless needs_force

        terminal.force_cleanup
      rescue StandardError => e
        @logger_ref&.error('Menu terminal force cleanup failed', error: e.message)
      end

      def log_exit(message, error)
        @logger_ref&.info('Exiting menu', message: message, status: error ? 'error' : 'ok')
        return unless error

        @logger_ref&.error('Menu exit error', error: error.message, backtrace: Array(error.backtrace))
      end

      def file_exists?(path)
        @file_probe&.exist?(path)
      end
    end
  end
end
