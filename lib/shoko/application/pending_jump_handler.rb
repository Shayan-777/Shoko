# frozen_string_literal: true

require_relative '../core/ports/outbound/annotation_editor_launcher'
require_relative '../core/ports/outbound/rendered_content_reader'
require_relative '../core/models/pending_jump_payload'
require_relative '../core/models/annotation_selection'

module Shoko
  module Application
    # Applies a pending jump payload captured in state before reader starts.
    class PendingJumpHandler
      def initialize(reader_state:, state_writer:, annotation_editor_launcher: nil, rendered_content_reader: nil,
                     navigation_service: nil, selection_service: nil,
                     coordinate_service: nil)
        if annotation_editor_launcher &&
           !annotation_editor_launcher.is_a?(Shoko::Core::Ports::Outbound::AnnotationEditorLauncher)
          raise ArgumentError, 'annotation_editor_launcher must implement Core::Ports::Outbound::AnnotationEditorLauncher'
        end
        if rendered_content_reader &&
           !rendered_content_reader.is_a?(Shoko::Core::Ports::Outbound::RenderedContentReader)
          raise ArgumentError, 'rendered_content_reader must implement Core::Ports::Outbound::RenderedContentReader'
        end

        @reader_state = reader_state
        @state_writer = state_writer
        @annotation_editor_launcher = annotation_editor_launcher
        @rendered_content_reader = rendered_content_reader
        @navigation_service = navigation_service
        @selection_service = selection_service
        @coordinate_service = coordinate_service
      end

      def apply
        pending_jump = @reader_state.pending_jump
        return unless pending_jump

        payload = normalize_payload(pending_jump)
        apply_chapter_jump(payload.chapter_index)
        apply_selection(payload.selection_range)
        open_annotation_editor(payload)
      ensure
        clear_pending_jump
      end

      private

      def apply_chapter_jump(chapter_index)
        return unless chapter_index

        @navigation_service&.jump_to_chapter(chapter_index)
      end

      def apply_selection(range)
        return unless range

        normalized = normalize_selection(range)
        return unless normalized

        @state_writer.update_reader(selection: normalized)
      end

      def open_annotation_editor(payload)
        return unless payload.edit == true

        annotation = payload.annotation
        return unless annotation

        return unless @annotation_editor_launcher
        unless annotation.is_a?(Shoko::Core::Models::AnnotationSelection)
          raise ArgumentError, 'pending_jump.annotation must be Core::Models::AnnotationSelection'
        end

        @annotation_editor_launcher.open_editor(
          text: annotation.text,
          range: annotation.range,
          chapter_index: annotation.chapter_index,
          annotation: annotation.to_annotation_h
        )
      end

      def normalize_selection(range)
        if @selection_service && @rendered_content_reader
          normalized = @selection_service.normalize_range(
            rendered_content_reader: @rendered_content_reader, selection_range: range
          )
          return normalized if normalized
        end

        return range unless @coordinate_service

        rendered = @rendered_content_reader&.rendered_lines
        @coordinate_service.normalize_selection_range(range, rendered)
      end

      def clear_pending_jump
        @state_writer.update_selections(pending_jump: nil)
      end

      def normalize_payload(payload)
        return payload if payload.is_a?(Shoko::Core::Models::PendingJumpPayload)

        Shoko::Core::Models::PendingJumpPayload.from_h(payload)
      end
    end
  end
end
