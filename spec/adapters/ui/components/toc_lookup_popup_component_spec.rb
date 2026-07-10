# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::TocLookupPopupComponent do
  let(:entries) do
    [
      { title: 'Chapter One', level: 0, current: true, navigable: true },
      { title: 'Chapter Two', level: 0, current: false, navigable: true },
      { title: 'Chapter Three', level: 0, current: false, navigable: true },
    ]
  end

  let(:toc_state) do
    { mode: :toc, toc_visible_entries: entries, toc_selected_index: 0, overlay_hover_index: nil, toc_query: '' }
  end
  let(:reader_state_reader) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter, **toc_state) }

  subject(:component) { described_class.new(reader_state_reader: reader_state_reader) }

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 100, height: 20) }

  before { terminal.reset! }

  describe '#visible?' do
    it 'tracks TOC mode from state' do
      expect(component).to be_visible

      allow(reader_state_reader).to receive(:mode).and_return(:read)
      expect(component).not_to be_visible
    end
  end

  describe '#hit_test' do
    it 'maps each entry row to its index and a click above to a dismiss' do
      component.render(surface, bounds)
      rule = terminal.writes.map { |write| write[:row] }.min

      expect(component.hit_test(3, rule + 1)).to eq(0)
      expect(component.hit_test(3, rule + 2)).to eq(1)
      expect(component.hit_test(3, rule + 3)).to eq(2)
      expect(component.hit_test(3, rule)).to eq(:inside)
      expect(component.hit_test(3, rule - 1)).to eq(:outside)
    end

    it 'has no hit geometry when TOC mode is inactive' do
      allow(reader_state_reader).to receive(:mode).and_return(:read)
      component.render(surface, bounds)

      expect(component.hit_test(3, 10)).to eq(:inside)
    end
  end
end
