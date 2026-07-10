# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::NotesLookupController do
  def success_outcome(code: :ok, status: :handled)
    Shoko::Shared::Contracts::SessionOutcome.success(status: status, code: code, payload: nil)
  end

  let(:notes_ui_session) do
    instance_double(
      Shoko::Adapters::Ui::Sessions::NotesUiSessionAdapter,
      open: success_outcome(code: :notes_opened, status: :opened),
      close: success_outcome(code: :notes_closed, status: :closed),
      apply_selection: success_outcome,
      begin_compose: success_outcome,
      write_draft: success_outcome,
      write_cursor: success_outcome,
      end_compose: success_outcome,
      visible?: true
    )
  end
  let(:annotation_service) { instance_double(Shoko::Core::Services::AnnotationService, add: nil, update: nil) }
  let(:captured_quote_anchor) { { quote: 'a highlighted quote', position: 0.2 } }
  let(:captured_position_anchor) { { position: 0.3 } }
  let(:state_controller) do
    instance_double(
      Shoko::Adapters::Input::Controllers::StateController,
      jump_to_annotation: nil,
      delete_annotation_by_id: 0,
      refresh_annotations: nil,
      capture_quote_anchor: captured_quote_anchor,
      capture_position_anchor: captured_position_anchor,
      page_for_annotation: 3
    )
  end
  let(:input_controller) { instance_double(Shoko::Adapters::Input::ReaderInputController, enter_modal_mode: nil, exit_modal_mode: nil) }
  let(:notification_service) { instance_double(Shoko::Adapters::Output::NotificationService, set_message: nil) }
  let(:reader_session_mutator) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator, update_reader: nil) }
  let(:selection_service) { instance_double(Shoko::Application::Services::SelectionService, extract_text: 'a  highlighted   quote') }
  let(:rendered_content_reader) { instance_double(Shoko::Application::Ports::Outbound::RenderedContentReader, rendered_lines: { 1 => {} }) }

  let(:existing_note) do
    { 'id' => 'note-1', 'text' => 'quoted text', 'note' => 'my thought',
      'chapter_index' => 2, 'anchor' => { 'quote' => 'quoted text' } }
  end

  let(:state) do
    {
      annotations: [existing_note],
      notes_selected_index: 0,
      notes_composing: false,
      notes_draft: '',
      notes_cursor: 0,
      notes_editing_id: nil,
      notes_editing_text: '',
      notes_editing_anchor: nil,
      notes_editing_chapter: nil,
      current_chapter: 4,
      book_path: '/books/sample.epub',
      selection: nil,
      mode: :notes,
    }
  end

  let(:reader_state) do
    rs = instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter)
    state.each_key { |field| allow(rs).to receive(field) { state[field] } }
    rs
  end

  subject(:controller) do
    described_class.new(
      reader_state: reader_state,
      reader_session_mutator: reader_session_mutator,
      state_controller: state_controller,
      notes_ui_session: notes_ui_session,
      annotation_service: annotation_service,
      selection_service: selection_service,
      rendered_content_reader: rendered_content_reader,
      input_controller: input_controller,
      notification_service: notification_service,
      logger: nil
    )
  end

  def edit_op(operation, text = nil)
    Shoko::Application::UseCases::Requests::EditOp.new(operation: operation, text: text)
  end

  describe '#open_notes_lookup' do
    it 'opens into the browsable list with the list hint when no payload is given' do
      expect(controller.open_notes_lookup).to eq(:handled)

      expect(notes_ui_session).to have_received(:open)
      expect(input_controller).to have_received(:enter_modal_mode).with(:notes)
      expect(notes_ui_session).to have_received(:apply_selection).with(0)
      expect(notification_service).to have_received(:set_message).with(described_class::LIST_HINT, 3)
    end

    it 'republishes each note with its live page number when opening the list' do
      controller.open_notes_lookup

      # The state controller resolves each note's anchor against the live layout.
      expect(state_controller).to have_received(:page_for_annotation).with(existing_note)
      expect(reader_session_mutator).to have_received(:update_reader).with(
        annotations: [existing_note.merge(display_page: 3)]
      )
    end

    it 'opens straight into the compose editor when given a selection payload' do
      payload = { action: :annotate, data: { selection_range: { start: 0, end: 8 } } }

      expect(controller.open_notes_lookup(payload)).to eq(:handled)

      expect(state_controller).to have_received(:capture_quote_anchor).with(
        quote: 'a highlighted quote', chapter_index: 4, line_offset_hint: nil
      )
      expect(notes_ui_session).to have_received(:begin_compose).with(
        note: '', cursor: 0, editing_id: nil,
        editing_text: 'a highlighted quote',
        editing_anchor: captured_quote_anchor,
        editing_chapter: 4
      )
      expect(input_controller).to have_received(:enter_modal_mode).with(:notes_compose)
      expect(notification_service).to have_received(:set_message).with(described_class::COMPOSE_NEW_HINT, 3)
    end

    it 'passes when the session refuses to open' do
      allow(notes_ui_session).to receive(:open).and_return(
        Shoko::Shared::Contracts::SessionOutcome.failure(status: :error, code: :nope, message: 'no')
      )

      expect(controller.open_notes_lookup).to eq(:pass)
      expect(input_controller).not_to have_received(:enter_modal_mode)
    end
  end

  describe '#close_notes_lookup' do
    it 'closes the panel and leaves notes mode from the list face' do
      expect(controller.close_notes_lookup).to eq(:handled)

      expect(notes_ui_session).to have_received(:close)
      expect(input_controller).to have_received(:exit_modal_mode).with(:notes)
      expect(reader_session_mutator).to have_received(:update_reader).with(selection: nil)
    end

    it 'backs out to the list instead of closing while composing' do
      state[:notes_composing] = true

      expect(controller.close_notes_lookup).to eq(:handled)

      expect(notes_ui_session).to have_received(:end_compose)
      expect(notes_ui_session).not_to have_received(:close)
      expect(input_controller).to have_received(:exit_modal_mode).with(:notes_compose)
      expect(notification_service).to have_received(:set_message).with(described_class::LIST_HINT, 2)
    end
  end

  describe '#move_notes_selection' do
    it 'moves the selection clamped to the list bounds' do
      state[:annotations] = [existing_note, existing_note.merge('id' => 'note-2')]

      expect(controller.move_notes_selection(1)).to eq(:handled)
      expect(notes_ui_session).to have_received(:apply_selection).with(1)

      controller.move_notes_selection(5)
      expect(notes_ui_session).to have_received(:apply_selection).with(1).twice
    end

    it 'ignores movement while composing' do
      state[:notes_composing] = true

      expect(controller.move_notes_selection(1)).to eq(:handled)
      expect(notes_ui_session).not_to have_received(:apply_selection)
    end
  end

  describe '#confirm_notes_selection (list face)' do
    it 'jumps to the selected note and closes the panel' do
      expect(controller.confirm_notes_selection).to eq(:handled)

      expect(notes_ui_session).to have_received(:close)
      expect(input_controller).to have_received(:exit_modal_mode).with(:notes)
      expect(state_controller).to have_received(:jump_to_annotation).with(existing_note)
      expect(notification_service).to have_received(:set_message).with('Jumped to note', 2)
    end

    it 'nudges the user when there are no notes yet' do
      state[:annotations] = []

      controller.confirm_notes_selection

      expect(state_controller).not_to have_received(:jump_to_annotation)
      expect(notification_service).to have_received(:set_message)
        .with('No notes yet — highlight text and choose Annotate', 2)
    end
  end

  describe '#confirm_notes_selection (compose face)' do
    before { state[:notes_composing] = true }

    it 'refuses to save an empty page note' do
      state[:notes_draft] = '   '

      controller.confirm_notes_selection

      expect(annotation_service).not_to have_received(:add)
      expect(notification_service).to have_received(:set_message).with('Type your note first', 2)
    end

    it 'saves a new quote-anchored note through the annotation service' do
      state[:notes_draft] = 'remember this'
      state[:notes_editing_text] = 'quoted text'
      state[:notes_editing_anchor] = { quote: 'quoted text', position: 0.2 }
      state[:notes_editing_chapter] = 2

      controller.confirm_notes_selection

      expect(annotation_service).to have_received(:add) do |path, draft|
        expect(path).to eq('/books/sample.epub')
        expect(draft.note).to eq('remember this')
        expect(draft.text).to eq('quoted text')
        expect(draft.anchor).to eq({ quote: 'quoted text', position: 0.2 })
        expect(draft.chapter_index).to eq(2)
      end
      expect(notes_ui_session).to have_received(:end_compose)
      expect(input_controller).to have_received(:exit_modal_mode).with(:notes_compose)
      expect(notification_service).to have_received(:set_message).with('Note saved', 2)
    end

    it 'saves a page-level note when there is no anchored quote' do
      state[:notes_draft] = 'chapter thought'
      state[:notes_editing_anchor] = { position: 0.3 }

      controller.confirm_notes_selection

      expect(annotation_service).to have_received(:add) do |_path, draft|
        expect(draft.text).to eq('')
        expect(draft.anchor).to eq({ position: 0.3 })
        expect(draft.note).to eq('chapter thought')
      end
      expect(notification_service).to have_received(:set_message).with('Page note saved', 2)
    end

    it 'updates an existing note when editing' do
      state[:notes_draft] = 'revised thought'
      state[:notes_editing_id] = 'note-1'

      controller.confirm_notes_selection

      expect(annotation_service).to have_received(:update).with('/books/sample.epub', 'note-1', 'revised thought')
      expect(annotation_service).not_to have_received(:add)
      expect(notification_service).to have_received(:set_message).with('Note updated', 2)
    end

    it 'surfaces persistence failures as a message instead of crashing' do
      state[:notes_draft] = 'thought'
      allow(annotation_service).to receive(:add).and_raise(Shoko::AnnotationError.new(:add, 'disk full'))

      expect(controller.confirm_notes_selection).to eq(:handled)
      expect(notification_service).to have_received(:set_message).with(/Save failed/, 3)
    end
  end

  describe '#edit_selected_note' do
    it 'opens the compose editor seeded with the selected note' do
      expect(controller.edit_selected_note).to eq(:handled)

      expect(notes_ui_session).to have_received(:begin_compose).with(
        note: 'my thought', cursor: 'my thought'.length,
        editing_id: 'note-1', editing_text: 'quoted text',
        editing_anchor: { 'quote' => 'quoted text' }, editing_chapter: 2
      )
      expect(input_controller).to have_received(:enter_modal_mode).with(:notes_compose)
      expect(notification_service).to have_received(:set_message).with(described_class::COMPOSE_EDIT_HINT, 3)
    end

    it 'passes when there is nothing to edit' do
      state[:annotations] = []

      expect(controller.edit_selected_note).to eq(:pass)
      expect(notes_ui_session).not_to have_received(:begin_compose)
    end
  end

  describe '#new_note' do
    it 'starts a quote-anchored note when a live selection exists' do
      state[:selection] = { start: 3, end: 9 }

      expect(controller.new_note).to eq(:handled)

      expect(notes_ui_session).to have_received(:begin_compose).with(
        note: '', cursor: 0, editing_id: nil,
        editing_text: 'a highlighted quote', editing_anchor: captured_quote_anchor, editing_chapter: 4
      )
      expect(notification_service).to have_received(:set_message).with(described_class::COMPOSE_NEW_HINT, 3)
    end

    it 'starts a page-level note without a selection' do
      expect(controller.new_note).to eq(:handled)

      expect(state_controller).to have_received(:capture_position_anchor).with(chapter_index: 4)
      expect(notes_ui_session).to have_received(:begin_compose).with(
        note: '', cursor: 0, editing_id: nil,
        editing_text: '', editing_anchor: captured_position_anchor, editing_chapter: 4
      )
      expect(notification_service).to have_received(:set_message).with(described_class::COMPOSE_PAGE_HINT, 3)
    end
  end

  describe '#delete_selected_note' do
    it 'deletes through the state controller and re-clamps the selection' do
      expect(controller.delete_selected_note).to eq(:handled)

      expect(state_controller).to have_received(:delete_annotation_by_id).with(existing_note)
      expect(notes_ui_session).to have_received(:apply_selection).with(0)
      expect(notification_service).to have_received(:set_message).with('Note deleted', 2)
    end

    it 'passes when there is nothing to delete' do
      state[:annotations] = []

      expect(controller.delete_selected_note).to eq(:pass)
      expect(state_controller).not_to have_received(:delete_annotation_by_id)
    end
  end

  describe '#edit_note_input' do
    before do
      state[:notes_composing] = true
      state[:notes_draft] = 'helo'
      state[:notes_cursor] = 3
    end

    it 'inserts printable characters at the caret' do
      controller.edit_note_input(edit_op(:insert, 'l'))

      expect(notes_ui_session).to have_received(:write_draft).with(text: 'hello', cursor: 4)
    end

    it 'inserts newlines for multi-line notes' do
      controller.edit_note_input(edit_op(:newline))

      expect(notes_ui_session).to have_received(:write_draft).with(text: "hel\no", cursor: 4)
    end

    it 'deletes backwards from the caret' do
      controller.edit_note_input(edit_op(:backspace))

      expect(notes_ui_session).to have_received(:write_draft).with(text: 'heo', cursor: 2)
    end

    it 'ignores edits while browsing the list' do
      state[:notes_composing] = false

      expect(controller.edit_note_input(edit_op(:insert, 'x'))).to eq(:handled)
      expect(notes_ui_session).not_to have_received(:write_draft)
    end
  end

  describe '#move_note_cursor' do
    before do
      state[:notes_composing] = true
      state[:notes_draft] = 'hello'
      state[:notes_cursor] = 3
    end

    it 'moves the caret left, right, and to the line ends' do
      controller.move_note_cursor(:left)
      expect(notes_ui_session).to have_received(:write_cursor).with(2)

      controller.move_note_cursor(:home)
      expect(notes_ui_session).to have_received(:write_cursor).with(0)

      controller.move_note_cursor(:end)
      expect(notes_ui_session).to have_received(:write_cursor).with(5)
    end

    it 'does not write when the caret would not move' do
      state[:notes_cursor] = 0

      controller.move_note_cursor(:left)
      expect(notes_ui_session).not_to have_received(:write_cursor)
    end
  end
end
