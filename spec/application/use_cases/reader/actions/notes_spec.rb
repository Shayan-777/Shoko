# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Reader::Actions::Notes do
  let(:reader_notes_control) do
    instance_double(
      Shoko::Application::Ports::Outbound::ReaderNotesControl,
      open_notes_lookup: :handled,
      close_notes_lookup: :handled,
      move_notes_selection: :handled,
      confirm_notes_selection: :handled,
      edit_selected_note: :handled,
      new_note: :handled,
      delete_selected_note: :handled,
      edit_note_input: :handled,
      move_note_cursor: :handled
    )
  end

  subject(:use_case) { described_class.new(reader_notes_control: reader_notes_control) }

  it 'supports exactly the documented notes intents' do
    expect(described_class::SUPPORTED_INTENTS).to match_array(
      %i[open_notes close_notes notes_move_up notes_move_down notes_confirm
         notes_edit notes_new notes_delete edit_note note_cursor_move]
    )
  end

  it 'opens the panel, forwarding an optional selection payload' do
    payload = { data: { selection_range: { start: 1, end: 2 } } }

    expect(use_case.call(:open_notes, payload)).to eq(:handled)
    expect(reader_notes_control).to have_received(:open_notes_lookup).with(payload)

    use_case.call(:open_notes)
    expect(reader_notes_control).to have_received(:open_notes_lookup).with(nil)
  end

  it 'routes selection movement with the numeric delta' do
    delta = Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: -1)

    expect(use_case.call(:notes_move_up, delta)).to eq(:handled)
    expect(reader_notes_control).to have_received(:move_notes_selection).with(-1)
  end

  it 'routes the list/compose verbs to the control port' do
    use_case.call(:close_notes)
    use_case.call(:notes_confirm)
    use_case.call(:notes_edit)
    use_case.call(:notes_new)
    use_case.call(:notes_delete)

    expect(reader_notes_control).to have_received(:close_notes_lookup)
    expect(reader_notes_control).to have_received(:confirm_notes_selection)
    expect(reader_notes_control).to have_received(:edit_selected_note)
    expect(reader_notes_control).to have_received(:new_note)
    expect(reader_notes_control).to have_received(:delete_selected_note)
  end

  it 'routes compose-editor edits with the edit operation' do
    op = Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: 'x')

    expect(use_case.call(:edit_note, op)).to eq(:handled)
    expect(reader_notes_control).to have_received(:edit_note_input).with(op)
  end

  it 'routes caret movement with the direction' do
    move = Shoko::Application::UseCases::Requests::CursorMove.new(direction: :left)

    expect(use_case.call(:note_cursor_move, move)).to eq(:handled)
    expect(reader_notes_control).to have_received(:move_note_cursor).with(:left)
  end

  it 'rejects unsupported intents' do
    expect { use_case.call(:not_a_notes_intent) }.to raise_error(ArgumentError, /unsupported reader notes intent/)
  end
end
