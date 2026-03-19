# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_mode_switcher'
require_relative '../../../core/ports/outbound/annotation_selection_reader'
require_relative '../../../core/ports/outbound/annotation_view_refresher'
require_relative '../../../core/ports/outbound/reader_runner'
require_relative '../../../core/ports/outbound/menu_session_store'
require_relative '../../../core/ports/outbound/menu_transient_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/models/annotation_selection'
require_relative '../../../core/models/pending_jump_payload'
require_relative '../../../core/models/session/menu_snapshot'
require_relative '../../../core/models/session/menu_state_partition'

module Shoko
  module Application
    module Workflows
      module Menu
        class AnnotationWorkflow
          def initialize(
            mode_switcher:,
            menu_session_store:,
            reader_session_store:,
            annotation_service:,
            logger:,
            selected_annotation_reader:,
            annotations_view_refresher:,
            reader_runner:,
            menu_transient_store: nil
          )
            validate_dependencies!(
              mode_switcher: mode_switcher,
              menu_session_store: menu_session_store,
              reader_session_store: reader_session_store,
              annotation_service: annotation_service,
              selected_annotation_reader: selected_annotation_reader,
              annotations_view_refresher: annotations_view_refresher,
              reader_runner: reader_runner,
              menu_transient_store: menu_transient_store
            )
            assign_dependencies(
              mode_switcher: mode_switcher,
              menu_session_store: menu_session_store,
              reader_session_store: reader_session_store,
              annotation_service: annotation_service,
              logger: logger,
              selected_annotation_reader: selected_annotation_reader,
              annotations_view_refresher: annotations_view_refresher,
              reader_runner: reader_runner,
              menu_transient_store: menu_transient_store
            )
          end

          def open_selected_annotation
            selection = selected_annotation
            return unless selection

            pending_payload = Shoko::Core::Models::PendingJumpPayload.new(
              chapter_index: selection.chapter_index,
              selection_range: selection.range,
              annotation: selection,
              edit: false
            )
            @reader_session_store.save(
              current_reader.with(book_path: selection.book_path, pending_jump: pending_payload)
            )

            @reader_runner.run_reader(selection.book_path)
          end

          def open_selected_annotation_for_edit
            selection = selected_annotation
            return unless selection

            note_text = selection.note.to_s
            persist_menu_payload(
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
            persist_menu_payload(annotations_all: @annotation_service.list_all)

            @annotations_view_refresher.refresh_annotations_view
          end

          def save_current_annotation_edit
            context = current_annotation_edit_context
            return unless context

            @annotation_service.update(context[:path], context[:id], context[:text])
            persist_menu_payload(annotations_all: @annotation_service.list_all)

            @mode_switcher.switch_mode(:annotations)
            @annotations_view_refresher.refresh_annotations_view
          end

          private

          def selected_annotation
            @selected_annotation_reader.selected_annotation
          end

          def current_annotation_edit_context
            annotation = current_menu.selected_annotation || {}
            path = current_menu.selected_annotation_book
            text = current_menu.annotation_edit_text
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

          def current_menu
            return @menu_session_store.load unless @menu_transient_store

            Shoko::Core::Models::Session::MenuSnapshot.build(
              @menu_session_store.load.to_h.merge(@menu_transient_store.load.to_h)
            )
          end

          def current_reader
            @reader_session_store.load
          end

          def persist_menu_payload(payload)
            return @menu_session_store.save(current_menu.with(**payload)) unless @menu_transient_store

            session_attributes, transient_attributes =
              Shoko::Core::Models::Session::MenuStatePartition.split(payload)
            previous_session = @menu_session_store.load
            previous_transient = @menu_transient_store.load

            @menu_session_store.save(previous_session.with(**session_attributes)) unless session_attributes.empty?
            @menu_transient_store.save(previous_transient.with(**transient_attributes)) if transient_attributes.any?
          rescue Shoko::Error, ArgumentError
            rollback_menu_payload(previous_session, previous_transient, session_attributes, transient_attributes)
            raise
          end

          def rollback_menu_payload(previous_session, previous_transient, session_attributes, transient_attributes)
            @menu_session_store.save(previous_session) if previous_session && session_attributes&.any?
            return unless previous_transient && transient_attributes && !transient_attributes.empty?

            @menu_transient_store.save(previous_transient)
          rescue Shoko::Error, ArgumentError => e
            @last_menu_payload_rollback_error = e
          end

          def validate_dependencies!(mode_switcher:, menu_session_store:, reader_session_store:, annotation_service:,
                                     selected_annotation_reader:, annotations_view_refresher:, reader_runner:,
                                     menu_transient_store:)
            validate_contract!(mode_switcher, Shoko::Core::Ports::Outbound::MenuModeSwitcher,
                               'mode_switcher must implement Core::Ports::Outbound::MenuModeSwitcher')
            validate_contract!(selected_annotation_reader, Shoko::Core::Ports::Outbound::AnnotationSelectionReader,
                               'selected_annotation_reader must implement Core::Ports::Outbound::AnnotationSelectionReader')
            validate_contract!(annotations_view_refresher, Shoko::Core::Ports::Outbound::AnnotationViewRefresher,
                               'annotations_view_refresher must implement Core::Ports::Outbound::AnnotationViewRefresher')
            validate_contract!(reader_runner, Shoko::Core::Ports::Outbound::ReaderRunner,
                               'reader_runner must implement Core::Ports::Outbound::ReaderRunner')
            validate_contract!(menu_session_store, Shoko::Core::Ports::Outbound::MenuSessionStore,
                               'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore')
            validate_optional_contract!(menu_transient_store, Shoko::Core::Ports::Outbound::MenuTransientStore,
                                        'menu_transient_store must implement Core::Ports::Outbound::MenuTransientStore')
            validate_contract!(reader_session_store, Shoko::Core::Ports::Outbound::ReaderSessionStore,
                               'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore')
            raise ArgumentError, 'annotation_service is required' if annotation_service.nil?
          end

          def validate_contract!(value, contract, message)
            raise ArgumentError, message unless value.is_a?(contract)
          end

          def validate_optional_contract!(value, contract, message)
            return if value.nil? || value.is_a?(contract)

            raise ArgumentError, message
          end

          def assign_dependencies(
            mode_switcher:,
            menu_session_store:,
            reader_session_store:,
            annotation_service:,
            logger:,
            selected_annotation_reader:,
            annotations_view_refresher:,
            reader_runner:,
            menu_transient_store:
          )
            @mode_switcher = mode_switcher
            @menu_session_store = menu_session_store
            @menu_transient_store = menu_transient_store
            @reader_session_store = reader_session_store
            @annotation_service = annotation_service
            @logger = logger
            @selected_annotation_reader = selected_annotation_reader
            @annotations_view_refresher = annotations_view_refresher
            @reader_runner = reader_runner
          end
        end
      end
    end
  end
end
