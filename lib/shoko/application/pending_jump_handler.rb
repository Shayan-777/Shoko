# frozen_string_literal: true

require_relative '../application/ports/outbound/annotation_editor_launcher'
require_relative '../core/models/pending_jump_payload'
require_relative '../core/models/annotation_selection'
require_relative '../core/models/document_anchor'

module Shoko
  module Application
    # Applies a pending jump payload captured in state before reader starts.
    class PendingJumpHandler
      def initialize(reader_session_store:, annotation_editor_launcher: nil, anchor_resolver: nil,
                     navigation_service: nil)
        if annotation_editor_launcher &&
           !annotation_editor_launcher.is_a?(Shoko::Application::Ports::Outbound::AnnotationEditorLauncher)
          raise ArgumentError, 'annotation_editor_launcher must implement Application::Ports::Outbound::AnnotationEditorLauncher'
        end

        @reader_session_store = reader_session_store
        @annotation_editor_launcher = annotation_editor_launcher
        @anchor_resolver = anchor_resolver
        @navigation_service = navigation_service
      end

      def apply
        snapshot = @reader_session_store.load
        pending_jump = snapshot.pending_jump
        return unless pending_jump

        payload = normalize_payload(pending_jump)
        apply_anchor_jump(payload.chapter_index, payload.annotation)
        open_annotation_editor(payload)
      ensure
        clear_pending_jump
      end

      private

      # Land on the annotation's document anchor in the current layout: resolve
      # it to a wrapped-line offset and jump there, falling back to the chapter
      # start when it has no anchor or cannot be located.
      def apply_anchor_jump(chapter_index, annotation)
        return unless chapter_index
        return unless @navigation_service

        line_offset = annotation_line_offset(chapter_index, annotation)
        if line_offset
          @navigation_service.jump_to_chapter_offset(chapter_index, line_offset)
        else
          @navigation_service.jump_to_chapter(chapter_index)
        end
      end

      def annotation_line_offset(chapter_index, annotation)
        return nil unless @anchor_resolver
        return nil unless annotation.is_a?(Shoko::Core::Models::AnnotationSelection)

        anchor = Shoko::Core::Models::DocumentAnchor.from_h(annotation.anchor)
        return nil if anchor.nil? || anchor.empty?

        @anchor_resolver.line_offset_for(anchor, chapter_index: chapter_index)
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
          chapter_index: annotation.chapter_index,
          annotation: annotation.to_annotation_h
        )
      end

      def clear_pending_jump
        snapshot = @reader_session_store.load
        @reader_session_store.save(snapshot.with(pending_jump: nil))
      end

      def normalize_payload(payload)
        return payload if payload.is_a?(Shoko::Core::Models::PendingJumpPayload)

        Shoko::Core::Models::PendingJumpPayload.from_h(payload)
      end
    end
  end
end
