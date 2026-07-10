# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::NotesLookupPopupComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  let(:note) do
    { 'id' => 'note-1', 'text' => 'a quoted passage', 'note' => 'my thought about it',
      'chapter_index' => 1, 'display_page' => 12 }
  end

  let(:notes_state) do
    {
      mode: :notes,
      annotations: [note],
      notes_selected_index: 0,
      overlay_hover_index: nil,
      notes_composing: false,
      notes_draft: '',
      notes_cursor: 0,
      notes_editing_id: nil,
      notes_editing_text: '',
      notes_editing_chapter: nil,
    }
  end
  let(:reader_state_reader) do
    rs = instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter)
    notes_state.each_key { |field| allow(rs).to receive(field) { notes_state[field] } }
    rs
  end

  subject(:component) { described_class.new(reader_state_reader: reader_state_reader) }

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 100, height: 22) }

  before { terminal.reset! }

  def rendered_text
    strip_ansi(terminal.writes.map { |write| write[:text] }.join("\n"))
  end

  describe '#visible?' do
    it 'tracks notes mode from state' do
      expect(component).to be_visible

      allow(reader_state_reader).to receive(:mode).and_return(:read)
      expect(component).not_to be_visible
    end

    it 'renders nothing outside notes mode' do
      allow(reader_state_reader).to receive(:mode).and_return(:read)

      component.render(surface, bounds)

      expect(terminal.writes).to be_empty
    end
  end

  describe 'list face' do
    it 'renders the note text, its quote, and the count rule' do
      component.render(surface, bounds)

      expect(rendered_text).to include('my thought about it')
      expect(rendered_text).to include('a quoted passage')
      expect(rendered_text).to include('1 note')
    end

    it 'renders the empty-state hint when the book has no notes' do
      notes_state[:annotations] = []

      component.render(surface, bounds)

      expect(rendered_text).to include('No notes yet.')
      expect(rendered_text).to include('0 notes')
    end

    it 'maps clicks on a note block to its index and a click above to a dismiss' do
      notes_state[:annotations] = [note, note.merge('id' => 'note-2')]
      component.render(surface, bounds)
      rule = terminal.writes.map { |write| write[:row] }.min

      expect(component.hit_test(3, rule + 1)).to eq(0) # first note block (3 rows)
      expect(component.hit_test(3, rule + 3)).to eq(0)
      expect(component.hit_test(3, rule + 4)).to eq(1) # second note block
      expect(component.hit_test(3, rule)).to eq(:inside)
      expect(component.hit_test(3, rule - 1)).to eq(:outside)
    end
  end

  describe 'compose face' do
    before do
      notes_state[:notes_composing] = true
      notes_state[:notes_draft] = 'typing a new note'
      notes_state[:notes_cursor] = 17
      notes_state[:notes_editing_text] = 'a quoted passage'
    end

    it 'renders the draft inside the editor well' do
      component.render(surface, bounds)

      expect(rendered_text).to include('typing a new note')
    end

    it 'does not render the list while composing' do
      component.render(surface, bounds)

      expect(rendered_text).not_to include('my thought about it')
    end
  end
end
