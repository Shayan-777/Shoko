# frozen_string_literal: true

require_relative 'state/actions/update_selection_action'
require_relative '../application/selectors/reader_selectors'

module Shoko
  module Application
    # Adapter exposing the annotation editor overlay through the same interface as
    # the legacy screen component so Application commands can drive it via the input
    # dispatcher.
    class AnnotationEditorOverlaySession
      def initialize(state, _dependencies, ui_controller, annotation_service: nil)
        @state = state
        @ui_controller = ui_controller
        @annotation_service = annotation_service
      end

      def active?
        overlay = current_overlay
        overlay.respond_to?(:visible?) && overlay.visible?
      end

      def save_annotation
        overlay = current_overlay
        return :pass unless overlay

        service, book_path = resolve_save_context
        return cancel_and_pass unless service && book_path

        persist_annotation(overlay, service, book_path)
        :handled
      end

      def cancel_annotation
        close_overlay
        clear_selection
        @ui_controller.set_message('Annotation cancelled', 2)
        :handled
      end

      def cancel_and_pass
        cancel_annotation
        :pass
      end

      def handle_backspace
        overlay = current_overlay
        overlay&.handle_backspace
        :handled
      end

      def handle_enter
        overlay = current_overlay
        overlay&.handle_enter if overlay.respond_to?(:handle_enter)
        :handled
      end

      def handle_character(char)
        overlay = current_overlay
        overlay&.handle_character(char) if overlay.respond_to?(:handle_character)
        :handled
      end

      def handle_move_left
        overlay = current_overlay
        overlay&.handle_move_left if overlay.respond_to?(:handle_move_left)
        :handled
      end

      def handle_move_right
        overlay = current_overlay
        overlay&.handle_move_right if overlay.respond_to?(:handle_move_right)
        :handled
      end

      def handle_move_up
        overlay = current_overlay
        overlay&.handle_move_up if overlay.respond_to?(:handle_move_up)
        :handled
      end

      def handle_move_down
        overlay = current_overlay
        overlay&.handle_move_down if overlay.respond_to?(:handle_move_down)
        :handled
      end

      private

      def current_overlay
        Shoko::Application::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
      end

      def resolve_save_context
        service = resolve_annotation_service
        book_path = current_book_path
        [service, book_path]
      end

      def current_book_path
        return unless @ui_controller.respond_to?(:current_book_path)

        @ui_controller.current_book_path
      end

      def persist_annotation(overlay, service, book_path)
        save_overlay(overlay, service, book_path)
        refresh_annotations
      rescue StandardError => e
        @ui_controller.set_message("Save failed: #{e.message}", 3)
      ensure
        close_overlay
        clear_selection
      end

      def save_overlay(overlay, service, book_path)
        if overlay.annotation_id
          service.update(book_path, overlay.annotation_id, overlay.note)
          @ui_controller.set_message('Annotation updated', 2)
        else
          service.add(book_path,
                      overlay.selected_text,
                      overlay.note,
                      overlay.selection_range,
                      overlay.chapter_index,
                      nil)
          @ui_controller.set_message('Annotation saved!', 2)
        end
      end

      def refresh_annotations
        return unless @ui_controller.respond_to?(:refresh_annotations)

        @ui_controller.refresh_annotations
      end

      def resolve_annotation_service
        @annotation_service
      end

      def close_overlay
        return unless @ui_controller

        begin
          @ui_controller.send(:close_annotation_editor_overlay)
        rescue StandardError
          nil
        end
      end

      def clear_selection
        @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
      rescue StandardError
        nil
      end
    end
  end
end
