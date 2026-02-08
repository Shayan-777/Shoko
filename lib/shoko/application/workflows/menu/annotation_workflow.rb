# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        class AnnotationWorkflow
          def initialize(menu:, menu_state_reader:, menu_state_writer:, state_writer:, annotation_service:, logger:,
                         selected_annotation_reader:, refresh_annotations_view:, run_reader:)
            @menu = menu
            @menu_state_reader = menu_state_reader
            @menu_state_writer = menu_state_writer
            @state_writer = state_writer
            @annotation_service = annotation_service
            @logger = logger
            @selected_annotation_reader = selected_annotation_reader
            @refresh_annotations_view = refresh_annotations_view
            @run_reader = run_reader
          end

          def open_selected_annotation
            annotation, book_path = selected_annotation_and_path
            return unless annotation && book_path

            normalized = normalize_annotation(annotation)
            @state_writer.update_reader_meta(book_path: book_path)
            pending_payload = {
              chapter_index: normalized[:chapter_index],
              selection_range: normalized[:range],
              annotation: annotation,
              edit: false,
            }
            @state_writer.update_selections(pending_jump: pending_payload)

            @run_reader.call(book_path)
          end

          def open_selected_annotation_for_edit
            annotation, book_path = selected_annotation_and_path
            return unless annotation && book_path

            note_text = annotation[:note] || annotation['note'] || ''
            @menu_state_writer.update_menu(
              selected_annotation: annotation,
              selected_annotation_book: book_path,
              annotation_edit_text: note_text,
              annotation_edit_cursor: note_text.length
            )
            @menu.switch_to_mode(:annotation_editor)
          end

          def delete_selected_annotation
            annotation, book_path = selected_annotation_and_path
            return unless annotation && book_path

            ann_id = annotation[:id] || annotation['id']
            return unless ann_id

            begin
              @annotation_service&.delete(book_path, ann_id)
              @menu_state_writer.update_menu(annotations_all: @annotation_service&.list_all || {})
            rescue StandardError => e
              @logger&.error('Failed to delete annotation', error: e.message, path: book_path)
            end

            @refresh_annotations_view.call
          end

          def save_current_annotation_edit
            context = current_annotation_edit_context
            return unless context

            with_annotation_service do |service|
              service.update(context[:path], context[:id], context[:text])
              @menu_state_writer.update_menu(annotations_all: service.list_all)
            end

            @menu.switch_to_mode(:annotations)
            @refresh_annotations_view.call
          end

          private

          def selected_annotation_and_path
            selection = @selected_annotation_reader.call
            if selection.is_a?(Array)
              [selection[0], selection[1]]
            elsif selection.is_a?(Hash)
              [selection[:annotation] || selection['annotation'],
               selection[:book_path] || selection['book_path']]
            else
              [nil, nil]
            end
          rescue StandardError
            [nil, nil]
          end

          def normalize_annotation(annotation)
            return {} unless annotation.is_a?(Hash)

            annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
          end

          def current_annotation_edit_context
            annotation = @menu_state_reader.selected_annotation || {}
            path = @menu_state_reader.selected_annotation_book
            text = @menu_state_reader.annotation_edit_text
            return unless path && annotation

            ann_id = annotation[:id] || annotation['id']
            return unless ann_id

            { path: path, id: ann_id, text: text }
          end

          def with_annotation_service
            service = @annotation_service
            return unless service

            yield(service)
          rescue StandardError => e
            @logger&.error('Annotation service failure', error: e.message)
          end
        end
      end
    end
  end
end
