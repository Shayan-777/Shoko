# frozen_string_literal: true

require_relative 'mouseable_reader'
require_relative '../../adapters/input/dispatcher'
require_relative '../../adapters/output/ui/components/main_menu_component'
require_relative '../../adapters/output/ui/components/surface'
require_relative '../../adapters/output/ui/components/rect'
require_relative '../../adapters/output/ui/rendering/frame_coordinator'
require_relative '../../adapters/output/ui/rendering/render_pipeline'
require_relative '../main_menu/menu_progress_presenter'
require_relative 'menu/state_controller'
require_relative 'menu/input_controller'

module Shoko
  module Application::Controllers
    # Controller responsible for the menu orchestration loop.
    class MenuController
      include Shoko::Adapters::Input::KeyDefinitions::Helpers

      attr_accessor :filtered_epubs
      attr_reader :state, :main_menu_component, :catalog, :dependencies,
                  :terminal_service, :frame_coordinator, :render_pipeline,
                  :state_controller, :input_controller

      def initialize(dependencies = nil)
        @dependencies = dependencies || Shoko::Application::ContainerFactory.create_default_container
        setup_state
        setup_services
        setup_components
        @state_controller = Menu::StateController.new(self)
        @input_controller = Menu::InputController.new(self)
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
        case selectors.selected(state)
        when 0 then switch_to_browse
        when 1 then switch_to_mode(:library)
        when 2 then switch_to_mode(:annotations)
        when 3 then open_download_screen
        when 4 then switch_to_mode(:settings)
        when 5 then cleanup_and_exit(0, '')
        end
      end

      def handle_navigation(direction)
        current = selectors.selected(state)
        max_val = 5

        new_selected = case direction
                       when :up then [current - 1, 0].max
                       when :down then [current + 1, max_val].min
                       else current
                       end
        state.dispatch(menu_action(selected: new_selected))
      end

      def switch_to_browse
        state.dispatch(menu_action(mode: :browse, search_active: false))
        input_controller.activate(selectors.mode(state))
      end

      def switch_to_search
        state.dispatch(menu_action(mode: :search, search_active: true))
        input_controller.activate(selectors.mode(state))
      end

      def switch_to_mode(mode)
        payload = { mode: mode, browse_selected: 0 }
        payload[:settings_selected] = 1 if mode == :settings
        state.dispatch(menu_action(payload))
        preload_annotations if mode == :annotations
        input_controller.activate(selectors.mode(state))
      end

      def open_download_screen
        reset_download_state
        state.dispatch(menu_action(mode: :download))
        input_controller.activate(selectors.mode(state))
      end

      def download_start_search
        query = (state.get(%i[menu download_query]) || '').to_s
        state.dispatch(menu_action(mode: :download_search, download_cursor: query.length))
        input_controller.activate(selectors.mode(state))
      end

      def download_exit_search
        state.dispatch(menu_action(mode: :download))
        input_controller.activate(selectors.mode(state))
      end

      def download_submit_search
        query = (state.get(%i[menu download_query]) || '').to_s
        state_controller.search_downloads(query: query)
        download_exit_search
      end

      def download_refresh
        query = (state.get(%i[menu download_query]) || '').to_s
        state_controller.search_downloads(query: query)
      end

      def download_next_page
        next_url = state.get(%i[menu download_next])
        return unless next_url

        query = (state.get(%i[menu download_query]) || '').to_s
        state_controller.search_downloads(query: query, page_url: next_url)
      end

      def download_prev_page
        prev_url = state.get(%i[menu download_prev])
        return unless prev_url

        query = (state.get(%i[menu download_query]) || '').to_s
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
        exit code
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

      def toggle_kitty_images(_key = nil)
        settings_service.toggle_kitty_images
      end

      def toggle_page_numbering_mode(_key = nil)
        settings_service.toggle_page_numbering_mode
      end

      def wipe_cache(_key = nil)
        message = settings_service.wipe_cache(catalog: @catalog)
        @filtered_epubs = []
        @catalog.scan_message = message if @catalog.respond_to?(:scan_message)
        message
      end

      private

      def setup_state
        @state = @dependencies.resolve(:global_state)
        @filtered_epubs = []
      end

      def setup_services
        # Use dependency injection for services
        @catalog = @dependencies.resolve(:catalog_service)
        @terminal_service = @dependencies.resolve(:terminal_service)
        @frame_coordinator = Shoko::Adapters::Output::Ui::Rendering::FrameCoordinator.new(@dependencies)
        @render_pipeline = Shoko::Adapters::Output::Ui::Rendering::RenderPipeline.new(@dependencies)
      end

      def setup_components
        @main_menu_component = Shoko::Adapters::Output::Ui::Components::MainMenuComponent.new(self, @dependencies)
      end

      public

      # Library mode helpers
      def library_up
        current = selectors.browse_selected(state) || 0
        state.dispatch(menu_action(browse_selected: (current - 1).clamp(0, current)))
      end

      def library_down
        items = if main_menu_component&.current_screen.respond_to?(:items)
                  main_menu_component.current_screen.items
                else
                  []
                end
        max_index = [items.length - 1, 0].max
        current = selectors.browse_selected(state) || 0
        state.dispatch(menu_action(browse_selected: (current + 1).clamp(0, max_index)))
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

      # Legacy compatibility methods
      def browse_screen
        @main_menu_component.browse_screen
      end

      # recent_screen removed

      def settings_screen
        @main_menu_component.settings_screen
      end

      def download_books_screen
        @main_menu_component.download_books_screen
      end

      def annotations_screen
        @main_menu_component.annotations_screen
      end

      def annotation_editor_screen
        @main_menu_component.annotation_edit_screen
      end

      def menu_screen
        @main_menu_component.current_screen
      end

      def selected_book
        @main_menu_component.browse_screen.selected_book
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
        keys = read_input_keys
        input_controller.handle_keys(keys)
      end

      def read_input_keys
        @terminal_service.read_keys_blocking(limit: 10)
      end

      def process_scan_results_if_available
        return unless (epubs = @catalog.process_results)

        @filtered_epubs = epubs
        @main_menu_component.browse_screen.filtered_epubs = epubs
        @main_menu_component.library_screen.invalidate_cache!
      end

      def draw_screen
        notification_service&.tick(@state)
        @frame_coordinator.with_frame do |surface, bounds, _w, _h|
          @render_pipeline.render_component(surface, bounds, @main_menu_component)
        end
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
        return nil unless Shoko::Application::Selectors::MenuSelectors.mode(@state) == :annotation_editor

        @main_menu_component&.annotation_edit_screen
      end

      def notification_service
        @notification_service ||= begin
          @dependencies.resolve(:notification_service)
        rescue StandardError
          nil
        end
      end

      def logger
        @logger ||= begin
          @dependencies.resolve(:logger)
        rescue StandardError
          nil
        end
      end

      def settings_service
        @settings_service ||= @dependencies.resolve(:settings_service)
      end

      def selectors
        Shoko::Application::Selectors::MenuSelectors
      end

      def menu_action(payload)
        Shoko::Application::Actions::UpdateMenuAction.new(**payload)
      end

      def preload_annotations
        service = dependencies.resolve(:annotation_service)
        state.dispatch(menu_action(annotations_all: service.list_all))
      rescue StandardError
        state.dispatch(menu_action(annotations_all: {}))
      end

      def reset_download_state
        state.dispatch(menu_action(
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
                       ))
      end

      def update_download_selection(delta)
        results = Array(state.get(%i[menu download_results]))
        max_index = [results.length - 1, 0].max
        current = (state.get(%i[menu download_selected]) || 0).to_i
        new_val = (current + delta).clamp(0, max_index)
        state.dispatch(menu_action(download_selected: new_val))
      end

      def selected_download_book
        results = Array(state.get(%i[menu download_results]))
        index = (state.get(%i[menu download_selected]) || 0).to_i
        results[index]
      end

      def selected_library_item
        screen = main_menu_component&.current_screen
        items = screen.respond_to?(:items) ? screen.items : []
        index = selectors.browse_selected(state) || 0
        items[index]
      end

      def resolve_library_path(item)
        primary = item.respond_to?(:open_path) ? item.open_path : nil
        return primary if state_controller.valid_cache_path?(primary)

        fallback = item.respond_to?(:epub_path) ? item.epub_path : nil
        return fallback if fallback && !fallback.empty? && File.exist?(fallback)

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
          resolve_logger&.error('Menu terminal cleanup failed', error: e.message)
        ensure
          force_cleanup_if_needed(terminal, cleanup_error)
        end
      end

      def force_cleanup_if_needed(terminal, cleanup_error)
        return unless terminal.respond_to?(:force_cleanup)

        remaining_depth = Shoko::Adapters::Output::Terminal::TerminalService.session_depth || 0
        needs_force = cleanup_error || remaining_depth.positive?
        return unless needs_force

        terminal.force_cleanup
      rescue StandardError => e
        resolve_logger&.error('Menu terminal force cleanup failed', error: e.message)
      end

      def log_exit(message, error)
        logger = resolve_logger
        logger&.info('Exiting menu', message: message, status: error ? 'error' : 'ok')
        return unless error

        logger&.error('Menu exit error', error: error.message, backtrace: Array(error.backtrace))
      end

      def resolve_logger
        dependencies.resolve(:logger)
      rescue StandardError
        nil
      end
    end
  end
end
