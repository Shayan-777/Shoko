# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::AnnotationEditorOverlayComponent do
  subject(:component) do
    described_class.new(
      selected_text: 'Quoted text',
      range: { start: 0, length: 10 },
      chapter_index: 0
    )
  end

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }

  before do
    terminal.reset!
  end

  describe '#render and click handling' do
    it 'renders footer controls and maps click regions to save/cancel actions' do
      component.render(surface, bounds)
      regions = component.instance_variable_get(:@button_regions)

      save = regions.fetch(:save)
      cancel = regions.fetch(:cancel)

      expect(component.handle_click(save[:col], save[:row])).to eq(type: :save, note: '')
      expect(component.handle_click(cancel[:col], cancel[:row])).to eq(type: :cancel)
    end
  end

  describe '#handle_key' do
    it 'supports save and cancel shortcuts' do
      cancel_key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first

      expect(component.handle_key("\x13")).to eq(type: :save, note: '')
      expect(component.handle_key(cancel_key)).to eq(type: :cancel)
    end

    it 'edits note content via printable, newline, and backspace keys' do
      expect(component.note).to eq('')

      component.handle_key('a')
      component.handle_key("\n")
      component.handle_key('b')
      component.handle_key("\x7F")

      expect(component.note).to eq("a\n")
    end
  end

  describe 'overlay sizing' do
    it 'respects minimum overlay dimensions' do
      small_bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)
      layout = component.send(:overlay_layout, small_bounds)

      expect(layout.width).to be >= 46
      expect(layout.height).to be >= 12
    end
  end
end
