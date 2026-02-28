# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_mode_switcher'
require_relative '../../../core/ports/outbound/annotation_selection_reader'
require_relative '../../../core/ports/outbound/annotation_view_refresher'
require_relative '../../../core/ports/outbound/reader_runner'
require_relative '../../../core/ports/outbound/menu_workflow_state_reader'
require_relative '../../../core/ports/outbound/menu_workflow_state_writer'

module Shoko
  module Application
    module Workflows
      module Menu
        class AnnotationWorkflow
          def initialize(mode_switcher:, menu_state_reader:, menu_state_writer:, state_writer:, annotation_service:,
                         logger:, selected_annotation_reader:, annotations_view_refresher:, reader_runner:)
            unless mode_switcher.is_a?(Shoko::Core::Ports::Outbound::MenuModeSwitcher)
              raise ArgumentError, 'mode_switcher must implement Core::Ports::Outbound::MenuModeSwitcher'
            end
            unless selected_annotation_reader.is_a?(Shoko::Core::Ports::Outbound::AnnotationSelectionReader)
              raise ArgumentError, 'selected_annotation_reader must implement Core::Ports::Outbound::AnnotationSelectionReader'
            end
            unless annotations_view_refresher.is_a?(Shoko::Core::Ports::Outbound::AnnotationViewRefresher)
              raise ArgumentError, 'annotations_view_refresher must implement Core::Ports::Outbound::AnnotationViewRefresher'
            end
            unless reader_runner.is_a?(Shoko::Core::Ports::Outbound::ReaderRunner)
              raise ArgumentError, 'reader_runner must implement Core::Ports::Outbound::ReaderRunner'
            end
            unless menu_state_reader.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateReader)
              raise ArgumentError, 'menu_state_reader must implement Core::Ports::Outbound::MenuWorkflowStateReader'
            end
            unless menu_state_writer.is_a?(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
              raise ArgumentError, 'menu_state_writer must implement Core::Ports::Outbound::MenuWorkflowStateWriter'
            end

            @mode_switcher = mode_switcher
            @menu_state_reader = menu_state_reader
            @menu_state_writer = menu_state_writer
            @state_writer = state_writer
            @annotation_service = annotation_service
            @logger = logger
            @selected_annotation_reader = selected_annotation_reader
            @annotations_view_refresher = annotations_view_refresher
            @reader_runner = reader_runner
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

            @reader_runner.run_reader(book_path)
          end

          def open_selected_annotation_for_edit
            annotation, book_path = selected_annotation_and_path
            return unless annotation && book_path

            note_text = annotation[:note] || annotation['note'] || ''
            @menu_state_writer.set_annotation_state(
              selected_annotation: annotation,
              selected_annotation_book: book_path,
              annotation_edit_text: note_text,
              annotation_edit_cursor: note_text.length
            )
            @mode_switcher.switch_mode(:annotation_editor)
          end

          def delete_selected_annotation
            annotation, book_path = selected_annotation_and_path
            return unless annotation && book_path

            ann_id = annotation[:id] || annotation['id']
            return unless ann_id

            begin
              @annotation_service&.delete(book_path, ann_id)
              @menu_state_writer.set_annotation_state(annotations_all: @annotation_service&.list_all || {})
            # resilient-boundary
            rescue StandardError => e
              @logger&.error('Failed to delete annotation', error: e.message, path: book_path)
            end

            @annotations_view_refresher.refresh_annotations_view
          end

          def save_current_annotation_edit
            context = current_annotation_edit_context
            return unless context

            with_annotation_service do |service|
              service.update(context[:path], context[:id], context[:text])
              @menu_state_writer.set_annotation_state(annotations_all: service.list_all)
            end

            @mode_switcher.switch_mode(:annotations)
            @annotations_view_refresher.refresh_annotations_view
          end

          private

          def selected_annotation_and_path
            @selected_annotation_reader.selected_annotation_and_path
          # resilient-boundary
          rescue StandardError => e
            @logger&.debug('annotation.selection_read_failed', error: e.class.name, message: e.message)
            [nil, nil]
          end

          def normalize_annotation(annotation)
            return {} unless annotation.is_a?(Hash)

            annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
          end

          def current_annotation_edit_context
            annotation = @menu_state_reader.selected_annotation_record || {}
            path = @menu_state_reader.selected_annotation_book_path
            text = @menu_state_reader.annotation_editor_text
            return unless path && annotation

            ann_id = annotation[:id] || annotation['id']
            return unless ann_id

            { path: path, id: ann_id, text: text }
          end

          def with_annotation_service
            service = @annotation_service
            return unless service

            yield(service)
          # resilient-boundary
          rescue StandardError => e
            @logger&.error('Annotation service failure', error: e.message)
          end
        end
      end
    end
  end
end
