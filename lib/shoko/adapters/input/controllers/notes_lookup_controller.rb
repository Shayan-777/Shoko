# frozen_string_literal: true

require_relative 'support/message_notifier'
require_relative 'support/session_outcome_helpers'
require 'shoko/shared/text_sanitizer'
require 'shoko/core/models/annotation_draft'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Drives the annotation-notes panel as a first-class reader mode, the fifth
        # member of the bar-anchored family (in-book search, dictionary, TOC,
        # translator). It is two-faced, like the translator:
        #
        #   * list face — the book's notes render in a left-docked card while the bar
        #     becomes a quiet toolbar; ↑/↓ move the selection (state-store backed),
        #     ↵ jumps to the note's location, e edits it, n starts a new note, d/Del
        #     deletes it; and
        #   * compose face — a multi-line note editor *inside* the card (the
        #     translator's source well, reused), with printable keys inserting at the
        #     caret, ←/→/Home/End moving it, ↵ saving, Esc returning to the list.
        #
        # The list selection, the compose draft, and the caret live in the reader
        # view-state store and are written through the notes UI session (the card
        # re-renders from them); this controller owns the operations that need
        # adapter coordination: surface lifecycle + the two modal sub-modes,
        # persistence through the annotation service, and jumping/deleting through
        # the state controller.
        class NotesLookupController
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeHelpers

          AnnotationDraft = Shoko::Core::Models::AnnotationDraft

          LIST_HINT = 'Notes: ↑/↓ browse · ↵ go · e edit · n new · d delete · Esc'
          COMPOSE_NEW_HINT = 'New note on this quote: type · ↵ save · ⇧↵ newline · Esc back'
          COMPOSE_PAGE_HINT = 'New page note: type · ↵ save · ⇧↵ newline · Esc back'
          COMPOSE_EDIT_HINT = 'Editing note: ↵ save · ⇧↵ newline · Esc back'

          def initialize(reader_state:, reader_session_mutator:, state_controller:, notes_ui_session:,
                         annotation_service:, selection_service: nil, rendered_content_reader: nil,
                         input_controller: nil, notification_service: nil, logger: nil)
            @reader_state = reader_state
            @reader_session_mutator = reader_session_mutator
            @state_controller = state_controller
            @notes_ui_session = notes_ui_session
            @annotation_service = annotation_service
            @selection_service = selection_service
            @rendered_content_reader = rendered_content_reader
            @input_controller = input_controller
            @notification_service = notification_service
            @logger = logger
            raise ArgumentError, 'notification_service is required' if @notification_service.nil?
          end

          # Open the panel. A selection payload (from the popup "Annotate" action)
          # opens straight into the compose editor, anchored to that selection; the
          # `a` hotkey (nil payload) opens the browsable notes list.
          def open_notes_lookup(payload = nil)
            outcome = @notes_ui_session.open
            return :pass unless session_ok?(outcome)

            activate_notes_mode
            seed = selection_seed(payload)
            seed ? begin_seeded_note(seed) : open_list
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.open_failed', error: e.message)
            :pass
          end

          # Esc is contextual: from the compose editor it backs out to the list; from
          # the list it closes the panel entirely.
          def close_notes_lookup(_key = nil)
            return back_to_list if composing?
            return :pass unless @notes_ui_session.visible? || @reader_state.mode == :notes

            outcome = @notes_ui_session.close
            return :pass unless session_ok?(outcome)

            clear_selection
            deactivate_notes_mode
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.close_failed', error: e.message)
            :pass
          end

          def move_notes_selection(delta)
            count = notes.length
            return :handled if composing? || count.zero?

            target = (current_index + delta.to_i).clamp(0, count - 1)
            @notes_ui_session.apply_selection(target)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.move_failed', error: e.message)
            :pass
          end

          # ↵ : save (compose face) or jump to the selected note (list face).
          def confirm_notes_selection(_key = nil)
            composing? ? save_note : jump_to_selected
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.confirm_failed', error: e.message)
            :pass
          end

          # e : edit the selected note's text in the compose editor.
          def edit_selected_note(_key = nil)
            note = selected_note
            return :pass unless note

            text = note_value(note, :note).to_s
            @notes_ui_session.begin_compose(
              note: text, cursor: text.length,
              editing_id: note_value(note, :id),
              editing_text: note_value(note, :text).to_s,
              editing_range: note_value(note, :range),
              editing_chapter: note_value(note, :chapter_index)
            )
            enter_compose_mode
            set_message(COMPOSE_EDIT_HINT, 3)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.edit_failed', error: e.message)
            :pass
          end

          # n : start a new note. With a live text selection it is anchored to that
          # quote; otherwise it becomes a page/chapter-level note tied to the current
          # reading position (no specific quote/line).
          def new_note(_key = nil)
            seed = selection_seed(nil)
            seed ? begin_seeded_note(seed) : begin_page_note
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.new_failed', error: e.message)
            :pass
          end

          # d / Delete : remove the selected note.
          def delete_selected_note(_key = nil)
            note = selected_note
            return :pass unless note

            @state_controller.delete_annotation_by_id(note)
            publish_pages
            @notes_ui_session.apply_selection(current_index.clamp(0, [notes.length - 1, 0].max))
            set_message('Note deleted', 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.delete_failed', error: e.message)
            :pass
          end

          # Printable input + backspace/delete/newline, edited at the caret in the
          # compose draft.
          def edit_note_input(edit_op)
            return :handled unless composing?

            text = @reader_state.notes_draft.to_s
            cursor = clamp_cursor(@reader_state.notes_cursor.to_i, text.length)
            new_text, new_cursor = apply_edit(text, cursor, edit_op)
            @notes_ui_session.write_draft(text: new_text, cursor: new_cursor)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.edit_input_failed', error: e.message)
            :pass
          end

          # ←/→/Home/End in the compose editor.
          def move_note_cursor(direction)
            return :handled unless composing?

            text = @reader_state.notes_draft.to_s
            cursor = clamp_cursor(@reader_state.notes_cursor.to_i, text.length)
            target = case direction
                     when :left  then [cursor - 1, 0].max
                     when :right then [cursor + 1, text.length].min
                     when :home  then 0
                     when :end   then text.length
                     else cursor
                     end
            @notes_ui_session.write_cursor(target) if target != cursor
            :handled
          rescue Shoko::Error => e
            @logger&.debug('notes.cursor_move_failed', error: e.message)
            :pass
          end

          def refresh_theme(theme_context:)
            @notes_ui_session&.refresh_theme(color_mode: theme_context&.color_mode)
          end

          def notes_lookup_visible?
            @notes_ui_session.visible? == true
          end

          private

          # ----- compose: persistence -----

          def save_note
            path = current_path
            return back_to_list unless path && @annotation_service
            return unless note_saveable?

            persist_note(path)
            @notes_ui_session.end_compose
            exit_compose_mode
            clear_selection
            @state_controller.refresh_annotations if @state_controller.respond_to?(:refresh_annotations)
            publish_pages
            @notes_ui_session.apply_selection(current_index.clamp(0, [notes.length - 1, 0].max))
          rescue Shoko::Error => e
            set_message("Save failed: #{e.message}", 3)
          end

          # A note is saveable when it has something to anchor it: a highlighted quote
          # (range) or — for a page/chapter note — some typed text. Editing an
          # existing note (it already has an id) is always allowed.
          def note_saveable?
            return true if @reader_state.notes_editing_id
            return true if @reader_state.notes_editing_range
            return true unless @reader_state.notes_draft.to_s.strip.empty?

            set_message('Type your note first', 2)
            false
          end

          def persist_note(path)
            note_text = @reader_state.notes_draft.to_s
            id = @reader_state.notes_editing_id
            return update_note(path, id, note_text) if id

            range = @reader_state.notes_editing_range
            @annotation_service.add(path, AnnotationDraft.new(
                                            text: @reader_state.notes_editing_text.to_s, note: note_text,
                                            range: range, chapter_index: @reader_state.notes_editing_chapter,
                                            page_meta: current_page_meta
                                          ))
            set_message(range ? 'Note saved' : 'Page note saved', 2)
          end

          def update_note(path, id, note_text)
            @annotation_service.update(path, id, note_text)
            set_message('Note updated', 2)
          end

          # Store the reading-position line offset (not a fixed page number) so the
          # page can be recomputed live against the current pagination — i.e. it stays
          # correct after the terminal is resized. Captured at save time; the reading
          # position doesn't move while composing.
          def current_page_meta
            return nil unless @state_controller.respond_to?(:current_reading_position)

            position = @state_controller.current_reading_position
            position ? { offset: position[:line_offset] } : nil
          end

          # Recompute each note's current page from its stored position and republish
          # the list, so the displayed page always matches the live pagination. Called
          # on open and after every mutation (cheap: a page lookup per note).
          def publish_pages
            list = Array(@reader_state.annotations)
            return if list.empty?

            @reader_session_mutator.update_reader(annotations: list.map { |ann| enrich_with_page(ann) })
          end

          def enrich_with_page(annotation)
            return annotation unless annotation.is_a?(Hash)

            page = page_for(note_value(annotation, :chapter_index), note_value(annotation, :page_offset))
            annotation.merge(display_page: page)
          end

          def page_for(chapter_index, offset)
            return nil unless offset && @state_controller.respond_to?(:page_number_for)

            @state_controller.page_number_for(chapter_index, offset)
          end

          # ----- list: jumping -----

          def jump_to_selected
            note = selected_note
            return set_message('No notes yet — highlight text and choose Annotate', 2) unless note

            @notes_ui_session.close
            deactivate_notes_mode
            @state_controller.jump_to_annotation(note) if @state_controller.respond_to?(:jump_to_annotation)
            set_message('Jumped to note', 2)
          end

          # ----- compose: seeding from a selection -----

          def begin_seeded_note(seed)
            @notes_ui_session.begin_compose(
              note: '', cursor: 0, editing_id: nil,
              editing_text: seed[:text], editing_range: seed[:range], editing_chapter: seed[:chapter]
            )
            enter_compose_mode
            set_message(COMPOSE_NEW_HINT, 3)
          end

          # A page/chapter-level note: no quote, anchored to the current chapter (and
          # its page is captured at save time).
          def begin_page_note
            @notes_ui_session.begin_compose(
              note: '', cursor: 0, editing_id: nil,
              editing_text: '', editing_range: nil, editing_chapter: current_chapter
            )
            enter_compose_mode
            set_message(COMPOSE_PAGE_HINT, 3)
          end

          def open_list
            publish_pages
            @notes_ui_session.apply_selection(initial_selection)
            set_message(LIST_HINT, 3)
          end

          # Resolve the text/range/chapter to annotate from an explicit popup payload
          # or the live reader selection — returns { text:, range:, chapter: } or nil.
          def selection_seed(payload)
            range = payload_range(payload) || @reader_state.selection
            return nil unless range

            text = extract_selection_text(range)
            return nil if text.nil? || text.empty?

            { text: text, range: range, chapter: current_chapter }
          end

          def payload_range(payload)
            return nil unless payload.is_a?(Hash)

            payload.dig(:data, :selection_range) || payload[:selection_range]
          end

          def extract_selection_text(range)
            return nil unless @selection_service && @rendered_content_reader

            text = @selection_service.extract_text(range, @rendered_content_reader.rendered_lines)
            text.to_s.strip.gsub(/\s+/, ' ')
          end

          def clear_selection
            @reader_session_mutator&.update_reader(selection: nil)
          end

          # ----- compose: text editing -----

          def apply_edit(text, cursor, edit_op)
            case edit_op&.operation
            when :insert    then insert_at(text, cursor, edit_op.text.to_s)
            when :newline   then insert_at(text, cursor, "\n", literal: true)
            when :backspace then backspace_at(text, cursor)
            when :delete    then delete_at(text, cursor)
            else [text, cursor]
            end
          end

          def insert_at(text, cursor, char, literal: false)
            return [text, cursor] unless literal || Shoko::Shared::TextSanitizer.printable_char?(char)

            ["#{text[0...cursor]}#{char}#{text[cursor..]}", cursor + char.length]
          end

          def backspace_at(text, cursor)
            return [text, cursor] if cursor <= 0

            ["#{text[0...(cursor - 1)]}#{text[cursor..]}", cursor - 1]
          end

          def delete_at(text, cursor)
            return [text, cursor] if cursor >= text.length

            ["#{text[0...cursor]}#{text[(cursor + 1)..]}", cursor]
          end

          def clamp_cursor(cursor, length)
            cursor.clamp(0, length)
          end

          # ----- mode plumbing -----

          def activate_notes_mode
            @input_controller&.enter_modal_mode(:notes)
          end

          def deactivate_notes_mode
            @input_controller&.exit_modal_mode(:notes)
          end

          def enter_compose_mode
            @input_controller&.enter_modal_mode(:notes_compose)
          end

          def exit_compose_mode
            @input_controller&.exit_modal_mode(:notes_compose)
          end

          def back_to_list
            @notes_ui_session.end_compose
            exit_compose_mode
            clear_selection
            set_message(LIST_HINT, 2)
            :handled
          end

          # ----- state helpers -----

          def notes
            Array(@reader_state.annotations)
          end

          def current_index
            (@reader_state.notes_selected_index || 0).to_i
          end

          def selected_note
            list = notes
            return nil if list.empty?

            list[current_index.clamp(0, list.length - 1)]
          end

          def initial_selection
            count = notes.length
            return 0 if count.zero?

            current_index.clamp(0, count - 1)
          end

          def composing?
            @reader_state.notes_composing == true
          end

          def current_chapter
            (@reader_state.current_chapter || 0).to_i
          end

          def current_path
            @reader_state.book_path
          end

          # Annotations are stored as hashes with string or symbol keys.
          def note_value(note, key)
            return nil unless note.is_a?(Hash)
            return note[key] if note.key?(key)

            note[key.to_s]
          end
        end
      end
    end
  end
end
