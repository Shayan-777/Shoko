# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Outbound control port for the in-book annotation-notes reader mode — the
        # fifth member of the bar-anchored family (in-book search, dictionary card,
        # TOC panel, translator). Implemented by the reader adapter; the notes use
        # case drives the panel lifecycle, list-selection movement, jumping to a
        # note, deleting it, and the in-card compose/edit editor through it.
        #
        # The list selection, the compose draft, and the caret position are
        # observable in the reader view-state store; these methods are the
        # operations that still need adapter coordination (surface lifecycle +
        # modal mode, persistence through the annotation service, jumping via the
        # state controller) plus the contextual input handling that routes the same
        # keys to either the list or the open compose editor.
        module ReaderNotesControl
          def open_notes_lookup(_payload = nil)
            raise NotImplementedError, "#{self.class} must implement #open_notes_lookup"
          end

          def close_notes_lookup
            raise NotImplementedError, "#{self.class} must implement #close_notes_lookup"
          end

          def move_notes_selection(_delta)
            raise NotImplementedError, "#{self.class} must implement #move_notes_selection"
          end

          def confirm_notes_selection
            raise NotImplementedError, "#{self.class} must implement #confirm_notes_selection"
          end

          def edit_selected_note
            raise NotImplementedError, "#{self.class} must implement #edit_selected_note"
          end

          def new_note
            raise NotImplementedError, "#{self.class} must implement #new_note"
          end

          def delete_selected_note
            raise NotImplementedError, "#{self.class} must implement #delete_selected_note"
          end

          def edit_note_input(_edit_op)
            raise NotImplementedError, "#{self.class} must implement #edit_note_input"
          end

          def move_note_cursor(_direction)
            raise NotImplementedError, "#{self.class} must implement #move_note_cursor"
          end
        end
      end
    end
  end
end
