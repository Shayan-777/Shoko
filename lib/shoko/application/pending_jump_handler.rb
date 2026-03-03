# frozen_string_literal: true

require_relative '../core/ports/outbound/annotation_editor_launcher'
require_relative '../core/ports/outbound/rendered_content_reader'

module Shoko
  module Application
    # Applies a pending jump payload captured in state before reader starts.
    class PendingJumpHandler
      COLLABORATOR_ERRORS = [ArgumentError, TypeError].freeze

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
        payload = @reader_state.pending_jump
        return unless payload

        apply_chapter_jump(payload)
        apply_selection(payload)
        open_annotation_editor(payload)
      ensure
        clear_pending_jump
      end

      private

      def apply_chapter_jump(payload)
        chapter_index = payload[:chapter_index] || payload['chapter_index']
        return unless chapter_index

        @navigation_service&.jump_to_chapter(chapter_index)
      rescue *COLLABORATOR_ERRORS
        nil
      end

      def apply_selection(payload)
        range = payload[:selection_range] || payload['selection_range']
        return unless range

        normalized = normalize_selection(range)
        return unless normalized

        @state_writer.update_reader(selection: normalized)
      end

      def open_annotation_editor(payload)
        return unless edit_requested?(payload)

        annotation = normalized_annotation(payload)
        return unless annotation

        return unless @annotation_editor_launcher

        @annotation_editor_launcher.open_editor(
          text: annotation[:text],
          range: annotation[:range],
          chapter_index: annotation[:chapter_index],
          annotation: annotation
        )
      rescue *COLLABORATOR_ERRORS
        nil
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
      rescue *COLLABORATOR_ERRORS
        nil
      end

      def clear_pending_jump
        @state_writer.update_selections(pending_jump: nil)
      end

      def truthy?(value)
        return value unless value.is_a?(String)

        !%w[false 0 no].include?(value.downcase)
      end

      def edit_requested?(payload)
        truthy?(payload[:edit] || payload['edit'])
      end

      def normalized_annotation(payload)
        raw = payload[:annotation] || payload['annotation']
        return unless raw

        {
          id: value_from(raw, :id),
          text: value_from(raw, :text),
          note: value_from(raw, :note),
          chapter_index: value_from(raw, :chapter_index),
          range: value_from(raw, :range),
        }
      end

      def value_from(hash, key)
        hash[key] || hash[key.to_s]
      end
    end
  end
end
