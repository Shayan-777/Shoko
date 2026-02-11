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
      key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first
      expect(component.handle_key(key)).to eq(type: :close)
    end
  end

  describe 'setup mode' do
    it 'enters setup mode and emits submit/change events' do
      component.show_setup(
        stage: :prompt_target,
        query: 'Haus',
        source_lang: 'en',
        input_value: 'de',
        suggestions: [{ code: 'de', label: 'German' }, { code: 'fr', label: 'French' }],
        suggestion_index: 0
      )
      expect(component).to be_setup_mode

      change = component.handle_key('f')
      expect(change).to eq(type: :setup_change, stage: :prompt_target, value: 'def')

      submit = component.handle_key("\n")
      expect(submit).to eq(type: :setup_submit, stage: :prompt_target, value: 'def')
    end

    it 'supports suggestion navigation and quick-apply keys' do
      component.show_setup(
        stage: :prompt_target,
        query: 'Haus',
        source_lang: 'en',
        input_value: '',
        suggestions: [{ code: 'de', label: 'German' }, { code: 'fr', label: 'French' }],
        suggestion_index: 0
      )

      down_key = Shoko::Shared::KeyDefinitions::NAVIGATION[:down].first
      select = component.handle_key(down_key)
      expect(select).to eq(type: :setup_select, stage: :prompt_target, index: 1, value: 'fr')

      apply = component.handle_key("\t")
      expect(apply).to eq(type: :setup_apply_suggestion, stage: :prompt_target, value: 'fr')
    end

    it 'emits a swap event on S in target stage' do
      component.show_setup(
        stage: :prompt_target,
        query: 'Haus',
        source_lang: 'en',
        input_value: 'de',
        suggestions: [{ code: 'de', label: 'German' }],
        suggestion_index: 0
      )

      expect(component.handle_key('S')).to eq(type: :setup_swap)
    end

    it 'keeps existing result mode behavior unchanged' do
      component.show(result)
      expect(component).not_to be_setup_mode
      key = Shoko::Shared::KeyDefinitions::NAVIGATION[:down].first
      expect(component.handle_key(key)).to eq(type: :scroll)
    end

    it 'renders structured setup lines without full reset codes' do
      component.show_setup(
        stage: :prompt_target,
        query: 'ideological',
        source_lang: 'en',
        target_lang: nil,
        input_value: 'de',
        prompt: 'Enter target language code for EN.',
        status: 'Downloading en-de.sqlite3... 65%',
        status_level: nil,
        progress: 0.65,
        suggestions: [{ code: 'de', label: 'German' }, { code: 'fr', label: 'French' }],
        suggestion_index: 0
      )

      lines = component.send(:build_setup_lines, 56)
      text = lines.join("\n")
      expect(text).to include('Dictionary Lookup')
      expect(text).to include('Step 2/2')
      expect(text).to include('[EN]')
      expect(text).not_to include("\e[0m")
      expect(text).to include('Suggestions')
    end

    it 'uses import-style progress bar glyphs in downloading stage' do
      component.show_setup(
        stage: :downloading,
        query: 'ideological',
        source_lang: 'en',
        target_lang: 'de',
        status: 'Downloading en-de.sqlite3... 65%',
        status_level: nil,
        progress: 0.65
      )

      text = component.send(:build_setup_lines, 40).join("\n")
      expect(text).to include('━')
      expect(text).not_to include('=')
    end
  end

  describe 'overlay sizing' do
    it 'respects minimum overlay dimensions' do
      bounds = Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)
      layout = component.send(:overlay_layout, bounds)
      expect(layout.width).to be >= 42
      expect(layout.height).to be >= 10
    end
  end
end
