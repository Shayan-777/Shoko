# frozen_string_literal: true

require 'spec_helper'

# DictionaryPopupComponent is now the first-run install wizard only; lookup
# results render in DictionaryLookupPopupComponent.
RSpec.describe Shoko::Adapters::Ui::Components::DictionaryPopupComponent do
  subject(:component) { described_class.new }

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*[ -\/]*[@-~]/, '')
  end

  describe '#render' do
    let(:terminal) { Shoko::TestSupport::TerminalDouble }
    let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
    let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }

    before do
      terminal.reset!
    end

    it 'renders setup content (not a blank popup)' do
      component.show_setup(
        stage: :prompt_target,
        query: 'Haus',
        source_lang: 'en',
        input_value: 'de',
        suggestions: [{ code: 'de', label: 'German' }]
      )

      expect { component.render(surface, bounds) }.not_to raise_error

      rendered_text = terminal.writes.map { |write| strip_ansi(write[:text]) }.join("\n")
      expect(rendered_text).to include('Dictionary Lookup')
      expect(rendered_text).to include('Word')
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
      expect(component).to be_visible

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

      down_key = Shoko::Adapters::Support::KeyDefinitions::NAVIGATION[:down].first
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

    it 'closes on the cancel key' do
      component.show_setup(stage: :prompt_target, query: 'Haus', source_lang: 'en', input_value: 'de')

      cancel = Shoko::Adapters::Support::KeyDefinitions::ACTIONS[:cancel].first
      expect(component.handle_key(cancel)).to eq(type: :close)
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
      component.show_setup(stage: :prompt_target, query: 'Haus', source_lang: 'en', input_value: 'de')
      bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20)
      layout = component.send(:overlay_layout, bounds)
      expect(layout.width).to be >= 42
      expect(layout.height).to be >= 10
    end
  end
end
