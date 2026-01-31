# frozen_string_literal: true

require_relative '../application/selectors/reader_selectors'

module Shoko
  module Application
    # Applies a pending jump payload captured in state before reader starts.
    class PendingJumpHandler
      def initialize(state, dependencies, ui_controller,
                     navigation_service: nil, selection_service: nil,
                     rendered_content_reader: nil, coordinate_service: nil,
                     render_registry: nil)
        @state = state
        @dependencies = dependencies
        @ui_controller = ui_controller
        @navigation_service = navigation_service
        @selection_service = selection_service
        @rendered_content_reader = rendered_content_reader
        @coordinate_service = coordinate_service
        @render_registry = render_registry
      end

      def apply
        payload = state.get(%i[reader pending_jump])
        return unless payload

        apply_chapter_jump(payload)
        apply_selection(payload)
        open_annotation_editor(payload)
      ensure
        clear_pending_jump
      end

      private

      attr_reader :state, :ui_controller

      def apply_chapter_jump(payload)
        chapter_index = payload[:chapter_index] || payload['chapter_index']
        return unless chapter_index

        @navigation_service&.jump_to_chapter(chapter_index)
      rescue StandardError
        nil
      end

      def apply_selection(payload)
        range = payload[:selection_range] || payload['selection_range']
        return unless range

        normalized = normalize_selection(range)
        return unless normalized

        state.dispatch(Shoko::Application::Actions::UpdateSelectionAction.new(normalized))
      end

      def open_annotation_editor(payload)
        return unless edit_requested?(payload)

        annotation = normalized_annotation(payload)
        return unless annotation

        ui_controller.open_annotation_editor_overlay(
          text: annotation[:text],
          range: annotation[:range],
          chapter_index: annotation[:chapter_index],
          annotation: annotation
        )
      rescue StandardError
        nil
      end

      def normalize_selection(range)
        if @selection_service.respond_to?(:normalize_range) && @rendered_content_reader
          normalized = @selection_service.normalize_range(
            rendered_content_reader: @rendered_content_reader, selection_range: range
          )
          return normalized if normalized
        end

        return range unless @coordinate_service

        rendered = @rendered_content_reader&.rendered_lines ||
                   Shoko::Application::Selectors::ReaderSelectors.rendered_lines(
                     state, render_registry: @render_registry
                   )
        @coordinate_service.normalize_selection_range(range, rendered)
      rescue StandardError
        nil
      end

      def clear_pending_jump
        state.dispatch(Shoko::Application::Actions::UpdateSelectionsAction.new(pending_jump: nil))
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
