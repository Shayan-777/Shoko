# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::DictionaryPopupComponent do
  let(:entry) { Shoko::Core::Models::DictionaryEntry.new(word: 'Haus', senses: ['house']) }
  let(:result) do
    Shoko::Core::Models::DictionaryResult.new(
      query: 'Haus',
      entries: [entry, entry],
      source_lang: 'de',
      target_lang: 'en',
      search_mode: :grouped
    )
  end

  subject(:component) { described_class.new }

  describe '#show and #hide' do
    it 'toggles visibility and resets state' do
      component.show(result)
      expect(component).to be_visible
      component.scroll_down(5)

      component.hide
      expect(component).not_to be_visible
      expect(component.scroll_offset).to eq(0)
      expect(component.result).to be_nil
    end
  end

  describe '#next_entry' do
    it 'cycles through entries when available' do
      component.show(result)
      expect(component.entry_index).to eq(0)
      expect(component.next_entry).to be(true)
      expect(component.entry_index).to eq(1)
    end

    it 'does not advance while in fuzzy mode' do
      component.show(result)
      component.toggle_fuzzy([Shoko::Core::Models::FuzzyMatch.new(word: 'Haus', similarity: 0.8)])
      expect(component.next_entry).to be(false)
    end
  end

  describe '#toggle_fuzzy' do
    it 'toggles fuzzy mode on and off' do
      component.show(result)
      component.toggle_fuzzy([Shoko::Core::Models::FuzzyMatch.new(word: 'Haus', similarity: 0.8)])
      expect(component).to be_fuzzy_mode

      component.toggle_fuzzy
      expect(component).not_to be_fuzzy_mode
    end
  end

  describe '#handle_key' do
    it 'returns close for cancel key' do
      component.show(result)
      key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:cancel].first
      expect(component.handle_key(key)).to eq(type: :close)
    end
  end

  describe 'overlay sizing' do
    it 'respects minimum overlay dimensions' do
      bounds = Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)
      layout = component.send(:overlay_layout, bounds)
      expect(layout.width).to be >= 50
      expect(layout.height).to be >= 15
    end
  end
end
