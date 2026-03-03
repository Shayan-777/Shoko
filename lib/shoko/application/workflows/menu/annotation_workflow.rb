# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_mode_switcher'
require_relative '../../../core/ports/outbound/annotation_selection_reader'
require_relative '../../../core/ports/outbound/annotation_view_refresher'
require_relative '../../../core/ports/outbound/reader_runner'
require_relative '../../../core/ports/outbound/menu_workflow_state_reader'
require_relative '../../../core/ports/outbound/menu_workflow_state_writer'
require_relative '../../../core/models/annotation_selection'
require_relative '../../../core/models/pending_jump_payload'

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
            raise ArgumentError, 'annotation_service is required' if annotation_service.nil?

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
            selection = selected_annotation
            return unless selection

            @state_writer.update_reader_meta(book_path: selection.book_path)
            pending_payload = Shoko::Core::Models::PendingJumpPayload.new(
              chapter_index: selection.chapter_index,
              selection_range: selection.range,
              annotation: selection,
              edit: false
            )
            @state_writer.update_selections(pending_jump: pending_payload)

            @reader_runner.run_reader(selection.book_path)
          end

          def open_selected_annotation_for_edit
            selection = selected_annotation
            return unless selection

            note_text = selection.note.to_s
            @menu_state_writer.set_annotation_state(
              selected_annotation: selection.to_annotation_h,
              selected_annotation_book: selection.book_path,
              annotation_edit_text: note_text,
              annotation_edit_cursor: note_text.length
            )
            @mode_switcher.switch_mode(:annotation_editor)
          end

          def delete_selected_annotation
            selection = selected_annotation
            return unless selection

            ann_id = selection.id
            return unless ann_id

            @annotation_service.delete(selection.book_path, ann_id)
            @menu_state_writer.set_annotation_state(annotations_all: @annotation_service.list_all)

            @annotations_view_refresher.refresh_annotations_view
          end

          def save_current_annotation_edit
            context = current_annotation_edit_context
            return unless context

            @annotation_service.update(context[:path], context[:id], context[:text])
            @menu_state_writer.set_annotation_state(annotations_all: @annotation_service.list_all)

            @mode_switcher.switch_mode(:annotations)
            @annotations_view_refresher.refresh_annotations_view
          end

          private

          def selected_annotation
            @selected_annotation_reader.selected_annotation
          end

          def current_annotation_edit_context
            annotation = @menu_state_reader.selected_annotation_record || {}
            path = @menu_state_reader.selected_annotation_book_path
            text = @menu_state_reader.annotation_editor_text
            return unless path
            unless annotation.is_a?(Hash)
              raise ArgumentError, "selected_annotation_record must be Hash, got #{annotation.class}"
            end

            ann_id = if annotation.key?(:id)
                       annotation[:id]
                     elsif annotation.key?('id')
                       raise ArgumentError, 'selected_annotation_record must use symbol keys'
                     end
            return unless ann_id

            { path: path, id: ann_id, text: text }
          end
        end
      end
    end
  end
end
