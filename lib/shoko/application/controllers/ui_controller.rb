# frozen_string_literal: true

require_relative 'sidebar_controller'
require_relative 'dictionary_controller'
require_relative 'annotation_overlay_controller'
require_relative 'in_book_search_controller'

module Shoko
  module Application::Controllers
    # Coordinates all UI-related functionality by delegating to specialized controllers.
    # This is a thin facade over: SidebarController, DictionaryController, AnnotationOverlayController
    class UIController
      # Raised when required dependencies are missing for a UI action.
      class MissingDependencyError < StandardError; end

      # Builds the annotation editor screen component for annotation editor mode.
      class AnnotationEditorMode
        def initialize(controller, annotation_service, component_factory)
          @controller = controller
          @annotation_service = annotation_service
          @component_factory = component_factory
        end

        def build_component(**)
          @component_factory.annotation_editor_screen(
            controller: @controller,
            annotation_service: @annotation_service,
            **
          )
        end
      end

      def initialize(reader_state:, config_reader:, state_writer:, sidebar_state:, ui_state:,
                     notification_service: nil, selection_service: nil,
                     rendered_content_reader: nil, clipboard_service: nil,
                     ui_component_factory: nil, input_controller: nil,
                     reader_controller: nil, state_controller: nil,
                     annotation_service: nil, dictionary_service: nil,
                     dictionary_catalog_service: nil,
                     terminal_service: nil, layout_metrics: nil, layout_service: nil,
                     document: nil, navigation_service: nil, bookmark_service: nil,
                     dictionary_ui_session: nil, in_book_search_ui_session: nil,
                     annotation_overlay_ui_session: nil,
                     render_registry: nil, settings_service: nil, logger: nil,
                     dictionary_availability: nil, dictionary_storage: nil,
                     runtime_config: nil, formatting_service: nil, clock: nil)
        @reader_state = reader_state
        @config_reader = config_reader
        @state_writer = state_writer
        @sidebar_state = sidebar_state
        @ui_state = ui_state
        @dependencies_hash = {
          notification_service: notification_service,
          selection_service: selection_service,
          rendered_content_reader: rendered_content_reader,
          clipboard_service: clipboard_service,
          ui_component_factory: ui_component_factory,
          input_controller: input_controller,
          reader_controller: reader_controller,
          state_controller: state_controller,
          annotation_service: annotation_service,
          render_registry: render_registry,
          logger: logger,
          runtime_config: runtime_config,
        }
        @notification_service = notification_service
        @selection_service = selection_service
        @rendered_content_reader = rendered_content_reader
        @clipboard_service = clipboard_service
        @ui_component_factory = ui_component_factory
        @input_controller = input_controller
        @reader_controller = reader_controller
        @state_controller = state_controller
        @annotation_service = annotation_service
        @dictionary_ui_session = dictionary_ui_session
        @in_book_search_ui_session = in_book_search_ui_session
        @annotation_overlay_ui_session = annotation_overlay_ui_session
        @logger = logger
        @current_mode = nil

        # Initialize specialized controllers
        @sidebar_controller = SidebarController.new(
          reader_state: reader_state,
          config_reader: config_reader,
          state_writer: state_writer,
          sidebar_state: sidebar_state,
          ui_state: ui_state,
          document: document,
          navigation_service: navigation_service,
          bookmark_service: bookmark_service,
          state_controller: state_controller,
          ui_controller: self,
          notification_service: notification_service,
          formatting_service: formatting_service,
          layout_service: layout_service
        )
        @dictionary_controller = DictionaryController.new(
          reader_state: reader_state,
          config_reader: config_reader,
          sidebar_state: sidebar_state,
          state_writer: state_writer,
          layout_metrics: layout_metrics,
          dictionary_service: dictionary_service,
          dictionary_catalog_service: dictionary_catalog_service,
          terminal_service: terminal_service,
          ui_component_factory: ui_component_factory,
          logger: logger,
          input_controller: input_controller,
          layout_service: layout_service,
          reader_controller: reader_controller,
          document: document,
          selection_service: selection_service,
          rendered_content_reader: rendered_content_reader,
          notification_service: notification_service,
          settings_service: settings_service,
          dictionary_availability: dictionary_availability,
          dictionary_storage: dictionary_storage,
          dictionary_ui_session: dictionary_ui_session,
          ui_controller: self,
          clock: clock
        )
        @annotation_controller = AnnotationOverlayController.new(
          reader_state: reader_state,
          state_writer: state_writer,
          ui_component_factory: ui_component_factory,
          state_controller: state_controller,
          reader_controller: reader_controller,
          input_controller: input_controller,
          annotation_service: annotation_service,
          annotation_overlay_ui_session: annotation_overlay_ui_session,
          notification_service: notification_service,
          logger: logger
        )
        @in_book_search_controller = InBookSearchController.new(
          reader_state: reader_state,
          state_writer: state_writer,
          ui_component_factory: ui_component_factory,
          document: document,
          input_controller: input_controller,
          reader_controller: reader_controller,
          state_controller: state_controller,
          in_book_search_ui_session: in_book_search_ui_session,
          notification_service: notification_service,
          logger: logger
        )
      end

      attr_reader :current_mode

      # Setter injection for circular dependency resolution — called after all
      # controllers are constructed in ReaderController to break the cycle.
      def input_controller=(controller)
        @input_controller = controller
        @dependencies_hash[:input_controller] = controller
        @dictionary_controller.input_controller = controller
        @annotation_controller.input_controller = controller
        @in_book_search_controller.input_controller = controller
      end

      def state_controller=(controller)
        @state_controller = controller
        @dependencies_hash[:state_controller] = controller
        @annotation_controller.state_controller = controller
        @sidebar_controller.state_controller = controller
        @in_book_search_controller.state_controller = controller
      end

      # Mode switching
      def switch_mode(mode, **)
        annotation_editor_mode =
          mode == :annotation_editor ? AnnotationEditorMode.new(self, @annotation_service, @ui_component_factory) : nil
        close_annotations_overlay unless annotation_editor_mode
        close_annotation_editor_overlay unless annotation_editor_mode
        @state_writer.update_reader(mode: mode)

        @current_mode = annotation_editor_mode&.build_component(**)

        begin
          @input_controller&.activate_for_mode(mode) if @input_controller.respond_to?(:activate_for_mode)
        rescue StandardError
          # If not available, ignore; read mode remains default
        end
      end

      # === Sidebar delegation ===
      def open_toc
        @sidebar_controller.open_toc
      end

      def open_bookmarks
        @sidebar_controller.open_bookmarks
      end

      def open_annotations_tab
        @sidebar_controller.open_annotations_tab
      end

      def activate_sidebar_tab(tab)
        @sidebar_controller.activate_sidebar_tab(tab)
      end

      def handle_sidebar_toc_click(index)
        @sidebar_controller.handle_sidebar_toc_click(index)
      end

      def set_sidebar_toc_selected(index)
        @sidebar_controller.set_sidebar_toc_selected(index)
      end

      def sidebar_down
        @sidebar_controller.sidebar_down
      end

      def sidebar_up
        @sidebar_controller.sidebar_up
      end

      def sidebar_select
        @sidebar_controller.sidebar_select
      end

      def sidebar_toggle_toc
        @sidebar_controller.sidebar_toggle_toc
      end

      def sidebar_visible?
        @sidebar_controller.sidebar_visible?
      end

      def close_sidebar_with_restore(tab)
        @sidebar_controller.close_sidebar_with_restore(tab)
      end

      # TOC helpers exposed for external use
      def toc_entries_for(doc)
        @sidebar_controller.toc_entries_for(doc)
      end

      def toc_collapsed_for(entries, raw = nil)
        @sidebar_controller.toc_collapsed_for(entries, raw)
      end

      def toc_visible_indices(entries, collapsed)
        @sidebar_controller.toc_visible_indices(entries, collapsed)
      end

      def toc_entry_has_children?(entries, index)
        @sidebar_controller.toc_entry_has_children?(entries, index)
      end

      # === Annotation overlay delegation ===
      def open_annotations
        @annotation_controller.open_annotations
      end

      def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        @annotation_controller.open_annotation_editor_overlay(
          text: text,
          range: range,
          chapter_index: chapter_index,
          annotation: annotation
        )
      end

      def show_annotations_overlay
        @annotation_controller.show_annotations_overlay
      end

      def close_annotations_overlay
        @annotation_controller.close_annotations_overlay
      end

      def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        @annotation_controller.show_annotation_editor_overlay(
          text: text,
          range: range,
          chapter_index: chapter_index,
          annotation: annotation
        )
      end

      def close_annotation_editor_overlay
        @annotation_controller.close_annotation_editor_overlay
      end

      def annotations_overlay_visible?
        @annotation_controller.annotations_overlay_visible?
      end

      def annotation_editor_visible?
        @annotation_controller.annotation_editor_visible?
      end

      def open_annotation_from_overlay(annotation)
        @annotation_controller.open_annotation_from_overlay(annotation)
      end

      def edit_annotation_from_overlay(annotation)
        @annotation_controller.edit_annotation_from_overlay(annotation)
      end

      def delete_annotation_from_overlay(annotation)
        @annotation_controller.delete_annotation_from_overlay(annotation)
      end

      def annotations_up
        @annotation_controller.annotations_up
      end

      def annotations_down
        @annotation_controller.annotations_down
      end

      def annotations_open
        @annotation_controller.annotations_open
      end

      def annotations_edit
        @annotation_controller.annotations_edit
      end

      def annotations_delete
        @annotation_controller.annotations_delete
      end

      def annotations_cancel
        @annotation_controller.annotations_cancel
      end

      def annotation_editor_insert_char(char)
        @annotation_controller.annotation_editor_insert_char(char)
      end

      def annotation_editor_backspace
        @annotation_controller.annotation_editor_backspace
      end

      def annotation_editor_enter
        @annotation_controller.annotation_editor_enter
      end

      def annotation_editor_move_left
        @annotation_controller.annotation_editor_move_left
      end

      def annotation_editor_move_right
        @annotation_controller.annotation_editor_move_right
      end

      def annotation_editor_move_up
        @annotation_controller.annotation_editor_move_up
      end

      def annotation_editor_move_down
        @annotation_controller.annotation_editor_move_down
      end

      def annotation_editor_cancel
        @annotation_controller.annotation_editor_cancel
      end

      def annotation_editor_save
        @annotation_controller.annotation_editor_save
      end

      def handle_annotation_editor_overlay_click(col, row)
        @annotation_controller.handle_annotation_editor_overlay_click(col, row)
      end

      def handle_annotation_editor_overlay_event(result)
        @annotation_controller.handle_annotation_editor_overlay_event(result)
      end

      def refresh_annotations
        @annotation_controller.refresh_annotations
      end

      def current_book_path
        @annotation_controller.current_book_path
      end

      # === Dictionary delegation ===
      def handle_lookup_action(action_data)
        @dictionary_controller.handle_lookup_action(action_data)
      end

      def show_dictionary_panel(result, announce: true)
        @dictionary_controller.show_dictionary_panel(result, announce: announce)
      end

      def show_dictionary_popup(result, announce: true)
        @dictionary_controller.show_dictionary_popup(result, announce: announce)
      end

      def close_dictionary(_key = nil)
        @dictionary_controller.close_dictionary
      end

      def dictionary_insert_char(char)
        @dictionary_controller.dictionary_insert_char(char)
      end

      def dictionary_backspace(key = nil)
        @dictionary_controller.dictionary_backspace(key)
      end

      def dictionary_confirm(key = nil)
        @dictionary_controller.dictionary_confirm(key)
      end

      def dictionary_cancel(key = nil)
        @dictionary_controller.dictionary_cancel(key)
      end

      def dictionary_tab(key = nil)
        @dictionary_controller.dictionary_tab(key)
      end

      def dictionary_swap_languages(key = nil)
        @dictionary_controller.dictionary_swap_languages(key)
      end

      def refresh_dictionary_display_mode(terminal_width:, terminal_height:)
        @dictionary_controller.refresh_dictionary_display_mode(
          terminal_width: terminal_width,
          terminal_height: terminal_height
        )
      end

      def dictionary_scroll_up(key = nil)
        @dictionary_controller.dictionary_scroll_up(key)
      end

      def dictionary_scroll_down(key = nil)
        @dictionary_controller.dictionary_scroll_down(key)
      end

      def dictionary_toggle_fuzzy(key = nil)
        @dictionary_controller.dictionary_toggle_fuzzy(key)
      end

      def dictionary_cycle_result(key = nil)
        @dictionary_controller.dictionary_cycle_result(key)
      end

      def dictionary_cycle_pair(key = nil)
        @dictionary_controller.dictionary_cycle_pair(key)
      end

      def active_dictionary_component
        @dictionary_controller.active_dictionary_component
      end

      # === In-book search delegation ===
      def open_in_book_search(key = nil)
        @in_book_search_controller.open_in_book_search(key)
      end

      def close_in_book_search(key = nil)
        @in_book_search_controller.close_in_book_search(key)
      end

      def in_book_search_insert_char(char)
        @in_book_search_controller.in_book_search_insert_char(char)
      end

      def in_book_search_backspace(key = nil)
        @in_book_search_controller.in_book_search_backspace(key)
      end

      def in_book_search_confirm(key = nil)
        @in_book_search_controller.in_book_search_confirm(key)
      end

      def in_book_search_cancel(key = nil)
        @in_book_search_controller.in_book_search_cancel(key)
      end

      def in_book_search_up(key = nil)
        @in_book_search_controller.in_book_search_up(key)
      end

      def in_book_search_down(key = nil)
        @in_book_search_controller.in_book_search_down(key)
      end

      def dictionary_visible?
        @dictionary_controller.dictionary_visible?
      end

      def in_book_search_visible?
        @in_book_search_controller.in_book_search_visible?
      end

      def determine_dictionary_display_mode(terminal_width, terminal_height)
        @dictionary_controller.determine_dictionary_display_mode(terminal_width, terminal_height)
      end

      # === UI config methods (kept in UIController) ===
      def show_help
        switch_mode(:help)
      end

      def toggle_view_mode
        @state_writer.toggle_view_mode
      end

      def increase_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@config_reader.line_spacing) || 1
        return unless current < 2

        @state_writer.update_config(line_spacing: modes[current + 1])
        @state_writer.update_page(last_width: 0)
      end

      def decrease_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@config_reader.line_spacing) || 1
        return unless current.positive?

        @state_writer.update_config(line_spacing: modes[current - 1])
        @state_writer.update_page(last_width: 0)
      end

      def toggle_page_numbering_mode
        current_mode = @config_reader.page_numbering_mode
        new_mode = current_mode == :absolute ? :dynamic : :absolute
        @state_writer.update_config(page_numbering_mode: new_mode)
        set_message("Page numbering: #{new_mode}")
      end

      # === Popup handling ===
      def handle_popup_action(action_data)
        action_type = action_data.is_a?(Hash) ? action_data[:action] : action_data

        case action_type
        when :create_annotation, 'Create Annotation'
          handle_create_annotation_action(action_data)
        when :copy_to_clipboard, 'Copy to Clipboard'
          handle_copy_to_clipboard_action(action_data)
        when :lookup, 'Look Up'
          handle_lookup_action(action_data)
          return # Don't cleanup popup state - dictionary overlay handles its own cleanup
        end

        skip_editor = %i[create_annotation].include?(action_type) || action_type == 'Create Annotation'
        cleanup_popup_state(skip_editor: skip_editor)
      end

      def cleanup_popup_state(skip_editor: false)
        @state_writer.update_reader(popup_menu: nil)
        @state_writer.clear_selection
        close_in_book_search
        close_annotations_overlay
        close_annotation_editor_overlay unless skip_editor
        begin
          @reader_controller&.send(:clear_selection!)
        rescue StandardError
          # Best-effort; ignore if not available
        end
      end

      def set_message(text, duration = 2)
        if @notification_service
          @notification_service.set_message(text, duration)
        else
          @state_writer.update_reader(message: text)
        end
      rescue StandardError
        @state_writer.update_reader(message: text)
      end

      private

      def handle_create_annotation_action(action_data)
        selection_range = if action_data.is_a?(Hash)
                            action_data[:data][:selection_range]
                          else
                            @reader_state.selection
                          end
        selected_text = extract_selected_text_from_selection(selection_range)
        close_annotations_overlay
        show_annotation_editor_overlay(text: selected_text,
                                       range: selection_range,
                                       chapter_index: @reader_state.current_chapter)
      end

      def handle_copy_to_clipboard_action(_action_data)
        clipboard_service = @clipboard_service
        selection = @reader_state.selection
        selected_text = extract_selected_text_from_selection(selection)

        if clipboard_service.available? && selected_text && !selected_text.strip.empty?
          success = clipboard_service.copy_with_feedback(selected_text) do |msg|
            set_message(msg)
          end
          set_message(' Failed to copy to clipboard') unless success
        else
          set_message(' Copy to clipboard not available')
        end
        switch_mode(:read)
      end

      def extract_selected_text_from_selection(selection_range)
        return nil unless @selection_service && @rendered_content_reader

        rendered_lines = @rendered_content_reader.rendered_lines
        @selection_service.extract_text(selection_range, rendered_lines)
      end
    end
  end
end
