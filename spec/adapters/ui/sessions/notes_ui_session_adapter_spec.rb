# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Sessions::NotesUiSessionAdapter do
  let(:popup) { instance_double('NotesLookupPopup', update_color_mode: nil) }
  let(:reader_state_reader) { instance_double('ReaderStateReader', notes_lookup_popup: nil, mode: :notes) }
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
  let(:ui_component_factory) { instance_double('UIFactory', notes_lookup_popup: popup) }
  let(:logger) { instance_double('Logger', error: nil) }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_component_factory,
      logger: logger
    )
  end

  it 'opens the notes panel, resets notes state, and enters notes mode' do
    outcome = session.open

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:notes_opened)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      notes_lookup_popup: popup,
      mode: :notes,
      popup_menu: nil,
      notes_selected_index: 0,
      notes_composing: false,
      notes_draft: '',
      notes_cursor: 0,
      notes_editing_id: nil,
      notes_editing_text: '',
      notes_editing_range: nil,
      notes_editing_chapter: nil
    )
  end

  it 'reuses an already-built popup instead of asking the factory again' do
    allow(reader_state_reader).to receive(:notes_lookup_popup).and_return(popup)

    session.open

    expect(ui_component_factory).not_to have_received(:notes_lookup_popup)
  end

  it 'closes the panel, clears notes state, and returns to read mode' do
    outcome = session.close

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:notes_closed)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      hash_including(notes_lookup_popup: nil, mode: :read, notes_composing: false, notes_draft: '')
    )
  end

  it 'writes the list selection' do
    outcome = session.apply_selection(3)

    expect(outcome.ok).to be(true)
    expect(reader_session_mutator).to have_received(:update_reader).with(notes_selected_index: 3)
  end

  it 'enters the compose editor with the draft and full edit context' do
    outcome = session.begin_compose(
      note: 'draft', cursor: 5, editing_id: 'note-1',
      editing_text: 'quote', editing_range: { start: 1, end: 2 }, editing_chapter: 4
    )

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:notes_compose_begun)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      notes_composing: true,
      notes_draft: 'draft',
      notes_cursor: 5,
      notes_editing_id: 'note-1',
      notes_editing_text: 'quote',
      notes_editing_range: { start: 1, end: 2 },
      notes_editing_chapter: 4
    )
  end

  it 'writes the draft text and caret together' do
    session.write_draft(text: 'hello', cursor: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(notes_draft: 'hello', notes_cursor: 5)
  end

  it 'leaves the compose editor but keeps the panel open' do
    outcome = session.end_compose

    expect(outcome.ok).to be(true)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      hash_including(notes_composing: false, notes_draft: '', notes_editing_id: nil)
    )
    expect(reader_session_mutator).not_to have_received(:update_reader).with(hash_including(mode: :read))
  end

  it 'reports visibility from the reader mode' do
    expect(session.visible?).to be(true)

    allow(reader_state_reader).to receive(:mode).and_return(:read)
    expect(session.visible?).to be(false)
  end

  it 'returns a failure outcome and logs when a state write raises' do
    allow(reader_session_mutator).to receive(:update_reader).and_raise(RuntimeError, 'boom')

    outcome = session.write_draft(text: 'x', cursor: 1)

    expect(outcome.ok).to be(false)
    expect(outcome.code).to eq(:notes_draft_failed)
    expect(outcome.message).to eq('boom')
    expect(logger).to have_received(:error)
  end

  it 'fails to open when the popup cannot be built' do
    allow(ui_component_factory).to receive(:notes_lookup_popup).and_raise(RuntimeError, 'factory down')

    outcome = session.open

    expect(outcome.ok).to be(false)
    expect(outcome.code).to eq(:notes_popup_unavailable)
    expect(reader_session_mutator).not_to have_received(:update_reader)
  end
end
