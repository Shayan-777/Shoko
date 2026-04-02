# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::DictionaryPanelComponent do
  class RecordingOutput
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(row, col, text)
      @writes << { row: row, col: col, text: text }
    end
  end

  let(:state) { instance_double('State') }
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

  subject(:component) { described_class.new(state) }

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

  describe '#preferred_width' do
    it 'hides the panel when terminal is too narrow' do
      component.show(result)
      expect(component.preferred_width(100)).to eq(:hidden)
    end

    it 'hides when available width is below minimum' do
      component.show(result)
      expect(component.preferred_width(140, 130)).to eq(:hidden)
    end

    it 'returns a width when space is available' do
      component.show(result)
      expect(component.preferred_width(160, 120)).to eq(40)
    end
  end

  describe '#next_entry' do
    it 'cycles through entries when available' do
      component.show(result)
      expect(component.entry_index).to eq(0)
      expect(component.next_entry).to eq(:advanced)
      expect(component.entry_index).to eq(1)
    end

    it 'does not advance while in fuzzy mode' do
      component.show(result)
      component.toggle_fuzzy([Shoko::Core::Models::FuzzyMatch.new(word: 'Haus', similarity: 0.8)])
      expect(component.next_entry).to be_nil
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
      key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first
      expect(component.handle_key(key)).to eq(type: :close)
    end
  end

  describe '#render' do
    it 'renders visible dictionary content without missing panel layout constants' do
      component.show(result)
      output = RecordingOutput.new
      surface = Shoko::Adapters::Ui::Components::Surface.new(output)
      bounds = Shoko::Adapters::Ui::Components::Rect.new(1, 1, 40, 20)

      expect { component.render(surface, bounds) }.not_to raise_error
      expect(output.writes).not_to be_empty
    end
  end
end
