# frozen_string_literal: true

require 'shoko/shared/contracts/session_outcome'

module Shoko
  module Adapters
    module Ui
      module Sessions
        # Adapter-owned lifecycle for the annotation-notes panel component. The panel
        # renders from the reader view-state store; this session owns the component
        # instance (create/teardown via the factory), the notes-mode flag, the
        # list-selection write, and the compose-editor writes (draft text + caret,
        # plus the edit context: which annotation is being edited and its anchor).
        #
        # Mirrors TocUiSessionAdapter / TranslatorUiSessionAdapter: a pure renderer
        # fed from state, with the document/persistence logic living in the
        # controller that drives this session.
        class NotesUiSessionAdapter
          RESCUABLE_ERRORS = [ArgumentError, TypeError, RuntimeError].freeze

          # Reset on open/close (and when leaving the compose editor).
          BLANK_NOTES_STATE = {
            notes_selected_index: 0,
            notes_composing: false,
            notes_draft: '',
            notes_cursor: 0,
            notes_editing_id: nil,
            notes_editing_text: '',
            notes_editing_anchor: nil,
            notes_editing_chapter: nil,
          }.freeze

          BLANK_COMPOSE_STATE = {
            notes_composing: false,
            notes_draft: '',
            notes_cursor: 0,
            notes_editing_id: nil,
            notes_editing_text: '',
            notes_editing_anchor: nil,
            notes_editing_chapter: nil,
          }.freeze

          def initialize(reader_state_reader:, reader_session_mutator:, ui_component_factory:, logger: nil)
            @reader_state_reader = reader_state_reader
            @reader_session_mutator = reader_session_mutator
            @ui_component_factory = ui_component_factory
            @logger = logger
          end

          def open
            popup = ensure_popup
            return failure_outcome(:error, :notes_popup_unavailable, 'Notes popup unavailable') unless popup

            @reader_session_mutator.update_reader(
              notes_lookup_popup: popup, mode: :notes, popup_menu: nil, **BLANK_NOTES_STATE
            )
            success_outcome(:opened, :notes_opened)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.open', e)
            failure_outcome(:error, :notes_open_failed, e.message)
          end

          def close
            @reader_session_mutator.update_reader(notes_lookup_popup: nil, mode: :read, **BLANK_NOTES_STATE)
            success_outcome(:closed, :notes_closed)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.close', e)
            failure_outcome(:error, :notes_close_failed, e.message)
          end

          def apply_selection(selected_index)
            @reader_session_mutator.update_reader(notes_selected_index: selected_index.to_i)
            success_outcome(:handled, :notes_selection_applied)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.apply_selection', e)
            failure_outcome(:error, :notes_apply_selection_failed, e.message)
          end

          # Enter the compose editor: seed the draft text/caret and the edit context
          # (the annotation id when editing an existing note — nil for a new one —
          # plus the highlighted excerpt and chapter the note is anchored to).
          def begin_compose(note:, cursor:, editing_id:, editing_text:, editing_anchor:, editing_chapter:)
            @reader_session_mutator.update_reader(
              notes_composing: true,
              notes_draft: note.to_s,
              notes_cursor: cursor.to_i,
              notes_editing_id: editing_id,
              notes_editing_text: editing_text.to_s,
              notes_editing_anchor: editing_anchor,
              notes_editing_chapter: editing_chapter
            )
            success_outcome(:handled, :notes_compose_begun)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.begin_compose', e)
            failure_outcome(:error, :notes_begin_compose_failed, e.message)
          end

          # Compose-editor write: the draft text plus the caret position (a character
          # index), kept together so the card always renders a caret that matches the
          # buffer.
          def write_draft(text:, cursor:)
            @reader_session_mutator.update_reader(notes_draft: text.to_s, notes_cursor: cursor.to_i)
            success_outcome(:handled, :notes_draft_written)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.write_draft', e)
            failure_outcome(:error, :notes_draft_failed, e.message)
          end

          def write_cursor(cursor)
            @reader_session_mutator.update_reader(notes_cursor: cursor.to_i)
            success_outcome(:handled, :notes_cursor_written)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.write_cursor', e)
            failure_outcome(:error, :notes_cursor_failed, e.message)
          end

          # Leave the compose editor and return to the list (the panel stays open).
          def end_compose
            @reader_session_mutator.update_reader(**BLANK_COMPOSE_STATE)
            success_outcome(:handled, :notes_compose_ended)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.end_compose', e)
            failure_outcome(:error, :notes_end_compose_failed, e.message)
          end

          def visible?
            @reader_state_reader.mode == :notes
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.visible?', e)
            false
          end

          def refresh_theme(color_mode:)
            popup = current_popup
            popup&.update_color_mode(color_mode) if popup.respond_to?(:update_color_mode)
            success_outcome(:handled, :notes_theme_refreshed)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.refresh_theme', e)
            failure_outcome(:error, :notes_theme_refresh_failed, e.message)
          end

          private

          def ensure_popup
            current_popup || @ui_component_factory.notes_lookup_popup(reader_state_reader: @reader_state_reader)
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.ensure_popup', e)
            nil
          end

          def current_popup
            @reader_state_reader.notes_lookup_popup
          rescue *RESCUABLE_ERRORS => e
            log_error('notes.session.current_popup', e)
            nil
          end

          def success_outcome(status, code, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: payload)
          end

          def failure_outcome(status, code, message, payload: nil)
            Shoko::Shared::Contracts::SessionOutcome.failure(status: status, code: code, message: message,
                                                             payload: payload)
          end

          def log_error(event, error)
            @logger&.error(event, error: error.class.name, message: error.message)
          end
        end
      end
    end
  end
end
