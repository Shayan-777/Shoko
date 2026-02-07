# frozen_string_literal: true

module Shoko
  module Application::Controllers
    # Handles all annotation overlay functionality: annotations overlay and annotation editor
    class AnnotationOverlayController
      # Raised when required dependencies are missing for an annotation action.
      class MissingDependencyError < StandardError; end

      def initialize(reader_state:, state_writer:, ui_component_factory: nil, state_controller: nil,
                     reader_controller: nil, input_controller: nil,
                     annotation_service: nil, notification_service: nil, logger: nil)
        @reader_state = reader_state
        @state_writer = state_writer
        @ui_component_factory = ui_component_factory
        @state_controller = state_controller
        @reader_controller = reader_controller
        @input_controller = input_controller
        @annotation_service = annotation_service
        @notification_service = notification_service
        @logger = logger
      end

      # Setter injection for circular dependency resolution — set after construction
      attr_writer :input_controller, :state_controller

      def open_annotations
        overlay = @reader_state.annotations_overlay
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
        raise MissingDependencyError, 'Dependency :ui_component_factory not available' unless @ui_component_factory

        overlay = @ui_component_factory.annotations_overlay(@reader_state)
        @state_writer.update_reader(annotations_overlay: overlay)
        set_message('Annotations overlay open (up/down navigate, Enter open, e edit, d delete)', 3)
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.show_annotations_overlay failed: #{e.message}")
        cleanup_annotations_overlay_fallback
      end

      def close_annotations_overlay
        overlay = @reader_state.annotations_overlay
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state_writer.update_reader(annotations_overlay: nil)
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.close_annotations_overlay failed: #{e.message}")
        cleanup_annotations_overlay_fallback
      end

      def show_annotation_editor_overlay(text:, range:, chapter_index:, annotation: nil)
        message = 'Annotation editor unavailable'
        raise MissingDependencyError, 'Dependency :ui_component_factory not available' unless @ui_component_factory

        overlay = @ui_component_factory.annotation_editor_overlay(
          selected_text: text,
          range: range,
          chapter_index: chapter_index,
          annotation: annotation
        )
        @state_writer.update_reader(annotation_editor_overlay: overlay)
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
        overlay = @reader_state.annotation_editor_overlay
        return unless overlay

        overlay.hide if overlay.respond_to?(:hide)
        @state_writer.update_reader(annotation_editor_overlay: nil)
        deactivate_annotation_editor_overlay_session
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.close_annotation_editor_overlay failed: #{e.message}")
        cleanup_annotation_editor_overlay_fallback
      end

      def open_annotation_from_overlay(annotation)
        with_normalized_annotation(annotation) do |normalized|
          @state_controller&.jump_to_annotation(normalized) if @state_controller.respond_to?(:jump_to_annotation)
          close_annotations_overlay
        end
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.open_annotation_from_overlay failed: #{e.message}")
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
          new_index = if @state_controller.respond_to?(:delete_annotation_by_id)
                        @state_controller.delete_annotation_by_id(normalized)
                      end

          overlay = @reader_state.annotations_overlay
          overlay.selected_index = new_index if overlay.respond_to?(:selected_index=) && !new_index.nil?

          annotations = @reader_state.annotations || []
          close_annotations_overlay if annotations.empty?
          set_message('Annotation deleted', 2)
        end
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.delete_annotation_from_overlay failed: #{e.message}")
        close_annotations_overlay
      end

      def handle_annotation_editor_overlay_event(result)
        overlay = @reader_state.annotation_editor_overlay
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
        @state_controller&.refresh_annotations if @state_controller.respond_to?(:refresh_annotations)
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.refresh_annotations failed: #{e.message}")
      end

      # Provide current book path for modes/components that need persistence context
      def current_book_path
        @reader_state.book_path
      end

      private

      def save_annotation_from_overlay(note, overlay)
        svc = @annotation_service
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
          @state_writer.clear_selection
        end
      end

      def cancel_annotation_editor_overlay
        close_annotation_editor_overlay
        set_message('Annotation cancelled', 2)
        @state_writer.clear_selection
      end

      def activate_annotation_editor_overlay_session
        raise MissingDependencyError, 'Dependency :reader_controller not available' unless @reader_controller
        raise MissingDependencyError, 'Dependency :input_controller not available' unless @input_controller

        @reader_controller.activate_annotation_editor_overlay_session
        @input_controller.enter_modal_mode(:annotation_editor)
        true
      rescue MissingDependencyError => e
        log_dependency_error(:activate_annotation_editor_overlay_session, e)
        false
      end

      def deactivate_annotation_editor_overlay_session
        @input_controller&.exit_modal_mode(:annotation_editor)
        @reader_controller&.deactivate_annotation_editor_overlay_session
      end

      def cleanup_annotations_overlay_fallback
        @state_writer.update_reader(annotations_overlay: nil)
      rescue StandardError => e
        @logger&.debug("AnnotationOverlayController.cleanup_annotations_overlay_fallback failed: #{e.message}")
        nil
      end

      def cleanup_annotation_editor_overlay_fallback
        @state_writer.update_reader(annotation_editor_overlay: nil)
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

      def set_message(text, duration = 2)
        if @notification_service
          @notification_service.set_message(nil, text, duration)
        else
          @state_writer.update_reader(message: text)
        end
      rescue StandardError
        @state_writer.update_reader(message: text)
      end

      def log_dependency_error(context, error)
        return unless @logger.respond_to?(:error)

        @logger.error('Annotation editor activation failed', context: context, error: error.message)
      rescue StandardError
        nil
      end
    end
  end
end
