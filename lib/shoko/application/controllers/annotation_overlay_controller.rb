# frozen_string_literal: true

require_relative '../../adapters/output/ui/components/annotations_overlay_component'
require_relative '../../adapters/output/ui/components/annotation_editor_overlay_component'

module Shoko
  module Application::Controllers
    # Handles all annotation overlay functionality: annotations overlay and annotation editor
    class AnnotationOverlayController
      # Raised when required dependencies are missing for an annotation action.
      class MissingDependencyError < StandardError; end

      def initialize(state, dependencies)
        @state = state
        @dependencies = dependencies
      end

      def open_annotations
        overlay = Application::Selectors::ReaderSelectors.annotations_overlay(@state)
        if overlay&.visible?
          close_annotations_overlay
        else
          show_annotations_overlay
        end
      end

      def open_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        show_annotation_editor_overlay(text: text,
                                       range: range,
                                       chapter_index: chapter_index,
                                       annotation: annotation)
      end

      def show_annotations_overlay
        overlay = Shoko::Adapters::Output::Ui::Components::AnnotationsOverlayComponent.new(@state)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations_overlay: overlay))
        set_message('Annotations overlay open (up/down navigate, Enter open, e edit, d delete)', 3)
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.show_annotations_overlay failed: #{e.message}")
        cleanup_annotations_overlay_fallback
      end

      def close_annotations_overlay
        overlay = Application::Selectors::ReaderSelectors.annotations_overlay(@state)
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations_overlay: nil))
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.close_annotations_overlay failed: #{e.message}")
        cleanup_annotations_overlay_fallback
      end

      def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        message = 'Annotation editor unavailable'
        overlay = Shoko::Adapters::Output::Ui::Components::AnnotationEditorOverlayComponent.new(
          selected_text: text,
          range: range,
          chapter_index: chapter_index,
          annotation: annotation
        )
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotation_editor_overlay: overlay))
        if activate_annotation_editor_overlay_session
          message = 'Annotation editor active (Ctrl+S save, Esc cancel)'
        else
          cleanup_annotation_editor_overlay_fallback
        end
      rescue StandardError => e
        cleanup_annotation_editor_overlay_fallback
        log_dependency_error(:show_annotation_editor_overlay, e)
      ensure
        set_message(message, 3)
      end

      def close_annotation_editor_overlay
        overlay = Application::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotation_editor_overlay: nil))
        deactivate_annotation_editor_overlay_session
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.close_annotation_editor_overlay failed: #{e.message}")
        cleanup_annotation_editor_overlay_fallback
      end

      def open_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          state_controller = @dependencies.resolve(:state_controller)
          state_controller.jump_to_annotation(normalized) if state_controller.respond_to?(:jump_to_annotation)
          close_annotations_overlay
        end
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.open_annotation_from_overlay failed: #{e.message}")
        close_annotations_overlay
      end

      def edit_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          close_annotations_overlay
          show_annotation_editor_overlay(text: normalized[:text],
                                         range: normalized[:range],
                                         chapter_index: normalized[:chapter_index],
                                         annotation: normalized)
        end
      end

      def delete_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          state_controller = @dependencies.resolve(:state_controller)
          new_index = if state_controller.respond_to?(:delete_annotation_by_id)
                        state_controller.delete_annotation_by_id(normalized)
                      end

          overlay = Application::Selectors::ReaderSelectors.annotations_overlay(@state)
          overlay.selected_index = new_index if overlay.respond_to?(:selected_index=) && !new_index.nil?

          annotations = @state.get(%i[reader annotations]) || []
          close_annotations_overlay if annotations.empty?
          set_message('Annotation deleted', 2)
        end
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.delete_annotation_from_overlay failed: #{e.message}")
        close_annotations_overlay
      end

      def handle_annotation_editor_overlay_event(result)
        overlay = Application::Selectors::ReaderSelectors.annotation_editor_overlay(@state)
        return unless overlay

        case result[:type]
        when :save
          save_annotation_from_overlay(result[:note], overlay)
        when :cancel
          cancel_annotation_editor_overlay
        end
      end

      # Refresh annotations from persistence into state
      def refresh_annotations
        state_controller = @dependencies.resolve(:state_controller)
        state_controller.refresh_annotations if state_controller.respond_to?(:refresh_annotations)
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.refresh_annotations failed: #{e.message}")
      end

      # Provide current book path for modes/components that need persistence context
      def current_book_path
        @state.get(%i[reader book_path])
      end

      private

      def save_annotation_from_overlay(note, overlay)
        svc = @dependencies.resolve(:annotation_service)
        path = current_book_path
        unless svc && path
          cancel_annotation_editor_overlay
          return
        end

        begin
          if overlay.annotation_id
            svc.update(path, overlay.annotation_id, note)
            set_message('Annotation updated', 2)
          else
            svc.add(path, overlay.selected_text, note, overlay.selection_range, overlay.chapter_index, nil)
            set_message('Annotation saved!', 2)
          end
          refresh_annotations
        rescue StandardError => e
          set_message("Save failed: #{e.message}", 3)
        ensure
          close_annotation_editor_overlay
          @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
        end
      end

      def cancel_annotation_editor_overlay
        close_annotation_editor_overlay
        set_message('Annotation cancelled', 2)
        @state.dispatch(Shoko::Application::Actions::ClearSelectionAction.new)
      end

      def activate_annotation_editor_overlay_session
        reader_controller = resolve_required(:reader_controller)
        input_controller = resolve_required(:input_controller)
        reader_controller.activate_annotation_editor_overlay_session
        input_controller.enter_modal_mode(:annotation_editor)
        true
      rescue MissingDependencyError => e
        log_dependency_error(:activate_annotation_editor_overlay_session, e)
        false
      end

      def deactivate_annotation_editor_overlay_session
        input_controller = resolve_optional(:input_controller)
        input_controller&.exit_modal_mode(:annotation_editor)
        reader_controller = resolve_optional(:reader_controller)
        reader_controller&.deactivate_annotation_editor_overlay_session
      end

      def cleanup_annotations_overlay_fallback
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotations_overlay: nil))
      rescue StandardError => e
        Shoko::Adapters::Monitoring::Logger.debug("AnnotationOverlayController.cleanup_annotations_overlay_fallback failed: #{e.message}")
        nil
      end

      def cleanup_annotation_editor_overlay_fallback
        @state.dispatch(Shoko::Application::Actions::UpdateReaderAction.new(annotation_editor_overlay: nil))
        deactivate_annotation_editor_overlay_session
      rescue StandardError
        nil
      end

      def normalize_annotation(annotation)
        return nil unless annotation.is_a?(Hash)

        annotation.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end
      end

      def with_normalized_annotation(annotation)
        normalized = normalize_annotation(annotation)
        return unless normalized

        yield normalized
      end

      def resolve_required(key)
        service = @dependencies.resolve(key)
        raise MissingDependencyError, "Dependency :#{key} not registered" unless service

        service
      rescue MissingDependencyError
        raise
      rescue StandardError => e
        raise MissingDependencyError, "Dependency :#{key} failed to resolve: #{e.message}"
      end

      def resolve_optional(key)
        @dependencies.resolve(key)
      rescue StandardError
        nil
      end

      def safe_resolve(name)
        @dependencies.resolve(name)
      rescue StandardError
        nil
      end

      def set_message(text, duration = 2)
        notifier = @dependencies.resolve(:notification_service)
        notifier.set_message(@state, text, duration)
      rescue StandardError
        @state.dispatch(Shoko::Application::Actions::UpdateMessageAction.new(text))
      end

      def log_dependency_error(context, error)
        logger = resolve_optional(:logger)
        return unless logger.respond_to?(:error)

        logger.error('Annotation editor activation failed', context: context, error: error.message)
      rescue StandardError
        nil
      end
    end
  end
end
