# frozen_string_literal: true

require_relative 'sidebar_controller'
require_relative 'dictionary_controller'
require_relative 'annotation_overlay_controller'
require_relative '../../adapters/output/ui/components/annotations_overlay_component'
require_relative '../../adapters/output/ui/components/annotation_editor_overlay_component'
require_relative '../../adapters/output/ui/components/dictionary_panel_component'
require_relative '../../adapters/output/ui/components/dictionary_popup_component'

module Shoko
  module Application::Controllers
    # Coordinates all UI-related functionality by delegating to specialized controllers.
    # This is a thin facade over: SidebarController, DictionaryController, AnnotationOverlayController
    class UIController
      # Raised when required dependencies are missing for a UI action.
      class MissingDependencyError < StandardError; end

      # Builds the annotation editor screen component for annotation editor mode.
      class AnnotationEditorMode
        def initialize(controller, dependencies)
          @controller = controller
          @dependencies = dependencies
        end

        def build_component(**)
          Shoko::Adapters::Output::Ui::Components::Screens::AnnotationEditorScreenComponent.new(
            @controller,
            **,
            dependencies: @dependencies
          )
        end
      end

      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
        @current_mode = nil

        # Initialize specialized controllers
        @sidebar_controller = SidebarController.new(state, dependencies)
        @dictionary_controller = DictionaryController.new(state, dependencies)
        @annotation_controller = AnnotationOverlayController.new(state, dependencies)
      end

      attr_reader :current_mode

      # Mode switching
      def switch_mode(mode, **)
        annotation_editor_mode =
          mode == :annotation_editor ? AnnotationEditorMode.new(self, @dependencies) : nil
        close_annotations_overlay unless annotation_editor_mode
        close_annotation_editor_overlay unless annotation_editor_mode
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(mode: mode))

        @current_mode = annotation_editor_mode&.build_component(**)

        begin
          input_controller = @dependencies.resolve(:input_controller)
          input_controller.activate_for_mode(mode) if input_controller.respond_to?(:activate_for_mode)
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

      def open_annotation_from_overlay(annotation)
        @annotation_controller.open_annotation_from_overlay(annotation)
      end

      def edit_annotation_from_overlay(annotation)
        @annotation_controller.edit_annotation_from_overlay(annotation)
      end

      def delete_annotation_from_overlay(annotation)
        @annotation_controller.delete_annotation_from_overlay(annotation)
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

      def close_dictionary
        @dictionary_controller.close_dictionary
      end

      def handle_dictionary_key(key)
        @dictionary_controller.handle_dictionary_key(key)
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

      def determine_dictionary_display_mode(terminal_width, terminal_height)
        @dictionary_controller.determine_dictionary_display_mode(terminal_width, terminal_height)
      end

      # === UI config methods (kept in UIController) ===
      def show_help
        switch_mode(:help)
      end

      def toggle_view_mode
        @state.dispatch(Shoko::Application::Actions::ToggleViewModeAction.new)
      end

      def increase_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get(%i[config line_spacing])) || 1
        return unless current < 2

        @state.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(line_spacing: modes[current + 1]))
        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(last_width: 0))
      end

      def decrease_line_spacing
        modes = %i[compact normal relaxed]
        current = modes.index(@state.get(%i[config line_spacing])) || 1
        return unless current.positive?

        @state.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(line_spacing: modes[current - 1]))
        @state.dispatch(Shoko::Application::Actions::UpdatePageAction.new(last_width: 0))
      end

      def toggle_page_numbering_mode
        current_mode = @state.get(%i[config page_numbering_mode])
        new_mode = current_mode == :absolute ? :dynamic : :absolute
        @state.dispatch(Shoko::Application::Actions::UpdateConfigAction.new(page_numbering_mode: new_mode))
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
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(popup_menu: nil))
        @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
        close_annotations_overlay
        close_annotation_editor_overlay unless skip_editor
        begin
          reader_controller = @dependencies.resolve(:reader_controller)
          reader_controller&.send(:clear_selection!)
        rescue StandardError
          # Best-effort; ignore if not available
        end
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
      end

      private

      def handle_create_annotation_action(action_data)
        selection_range = if action_data.is_a?(Hash)
                            action_data[:data][:selection_range]
                          else
                            @state.get(%i[reader selection])
                          end
        selected_text = extract_selected_text_from_selection(selection_range)
        close_annotations_overlay
        show_annotation_editor_overlay(text: selected_text,
                                       range: selection_range,
                                       chapter_index: @state.get(%i[reader current_chapter]))
      end

      def handle_copy_to_clipboard_action(_action_data)
        clipboard_service = @dependencies.resolve(:clipboard_service)
        selection = @state.get(%i[reader selection])
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
        selection_service = @dependencies.resolve(:selection_service)
        rendered_content_reader = @dependencies.resolve(:rendered_content_reader)
        if selection_service.respond_to?(:extract_from_state)
          selection_service.extract_from_state(@state, rendered_content_reader: rendered_content_reader,
                                                       selection_range: selection_range)
        else
          rendered_lines = rendered_content_reader.rendered_lines
          selection_service.extract_text(selection_range, rendered_lines)
        end
      end

      def safe_resolve(name)
        @dependencies.resolve(name)
      rescue StandardError
        nil
      end
    end
  end
end
