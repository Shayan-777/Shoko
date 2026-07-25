# frozen_string_literal: true

require 'shoko/application/ports/outbound/menu_mode_switcher'
require 'shoko/application/ports/outbound/annotation_selection_reader'
require 'shoko/application/ports/outbound/annotation_view_refresher'
require 'shoko/application/ports/outbound/reader_runner'
require 'shoko/application/ports/outbound/menu_session_store'
require 'shoko/application/ports/outbound/menu_transient_store'
require 'shoko/application/ports/outbound/reader_session_store'
require 'shoko/core/models/annotation_selection'
require 'shoko/core/models/pending_jump_payload'
require_relative '../../ports/outbound/state/menu_snapshot'
require_relative '../../ports/outbound/state/menu_state_partition'
require_relative '../../ports/outbound/menu_mode_switcher'
require_relative '../../ports/outbound/annotation_selection_reader'
require_relative '../../ports/outbound/annotation_view_refresher'
require_relative '../../ports/outbound/reader_runner'
require_relative '../../ports/outbound/menu_session_store'
require_relative '../../ports/outbound/menu_transient_store'
require_relative '../../ports/outbound/reader_session_store'
require_relative 'menu_state_persistence'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side annotation actions and reader handoff payloads.
        class AnnotationWorkflow
          include MenuStatePersistence

          def initialize(
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
            return cancel_current_annotation_edit unless context

            @annotation_service.update(context[:path], context[:id], context[:text])
            persist_menu_payload(annotations_all: @annotation_service.list_all)

            @mode_switcher.switch_mode(:annotations)
            @annotations_view_refresher.refresh_annotations_view
          end

          def cancel_current_annotation_edit
            @mode_switcher.switch_mode(:annotations)
          end

          REQUIRED_CONTRACTS = {
            mode_switcher: [
              Shoko::Application::Ports::Outbound::MenuModeSwitcher,
              'mode_switcher must implement Application::Ports::Outbound::MenuModeSwitcher',
            ],
            selected_annotation_reader: [
              Shoko::Application::Ports::Outbound::AnnotationSelectionReader,
              'selected_annotation_reader must implement Application::Ports::Outbound::AnnotationSelectionReader',
            ],
            annotations_view_refresher: [
              Shoko::Application::Ports::Outbound::AnnotationViewRefresher,
              'annotations_view_refresher must implement Application::Ports::Outbound::AnnotationViewRefresher',
            ],
            reader_runner: [
              Shoko::Application::Ports::Outbound::ReaderRunner,
              'reader_runner must implement Application::Ports::Outbound::ReaderRunner',
            ],
            menu_session_store: [
              Shoko::Application::Ports::Outbound::MenuSessionStore,
              'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore',
            ],
            reader_session_store: [
              Shoko::Application::Ports::Outbound::ReaderSessionStore,
              'reader_session_store must implement Application::Ports::Outbound::ReaderSessionStore',
            ],
          }.freeze

          REQUIRED_TRANSIENT_CONTRACTS = {
            menu_transient_store: [
              Shoko::Application::Ports::Outbound::MenuTransientStore,
              'menu_transient_store must implement Application::Ports::Outbound::MenuTransientStore',
            ],
          }.freeze

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

          def current_reader
            @reader_session_store.load
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

          def validate_dependencies!(mode_switcher:, menu_session_store:, reader_session_store:, annotation_service:,
                                     selected_annotation_reader:, annotations_view_refresher:, reader_runner:,
                                     menu_transient_store:)
            validate_required_contracts(
              mode_switcher: mode_switcher,
              selected_annotation_reader: selected_annotation_reader,
              annotations_view_refresher: annotations_view_refresher,
              reader_runner: reader_runner,
              menu_session_store: menu_session_store,
              reader_session_store: reader_session_store
            )
            validate_required_transient_contracts(menu_transient_store:)
            raise ArgumentError, 'annotation_service is required' if annotation_service.nil?
          end

          def validate_contract!(value, contract, message)
            raise ArgumentError, message unless value.is_a?(contract)
          end

          def validate_required_contracts(**values)
            REQUIRED_CONTRACTS.each do |name, (contract, message)|
              validate_contract!(values.fetch(name), contract, message)
            end
          end

          def validate_required_transient_contracts(menu_transient_store:)
            contract, message = REQUIRED_TRANSIENT_CONTRACTS.fetch(:menu_transient_store)
            validate_contract!(menu_transient_store, contract, message)
          end
        end
      end
    end
  end
end
