# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::DictionaryLookupPopupComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  let(:entry) do
    Shoko::Core::Models::DictionaryEntry.new(
      word: 'revolution',
      senses: ['a forcible overthrow of a government', 'a dramatic and wide-reaching change'],
      translations: ['Revolution']
    )
  end
  let(:result) do
    Shoko::Core::Models::DictionaryResult.new(
      query: 'revolution',
      entries: [entry],
      source_lang: 'de',
      target_lang: 'en',
      search_mode: :grouped
    )
  end

  let(:dictionary_state) do
    {
      mode: :dictionary,
      dictionary_result: result,
      dictionary_entry_index: 0,
      dictionary_selected_index: 0,
      overlay_hover_index: nil,
      dictionary_fuzzy_mode: false,
      dictionary_fuzzy_matches: [],
      dictionary_query: 'revolution',
    }
  end
  let(:reader_state_reader) { instance_double(Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter, **dictionary_state) }

  subject(:component) { described_class.new(reader_state_reader: reader_state_reader) }

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 100, height: 20) }

  before { terminal.reset! }

  def rendered_rows
    terminal.writes.group_by { |write| write[:row] }.transform_values do |writes|
      strip_ansi(writes.map { |write| write[:text] }.join)
    end
  end

  describe '#visible?' do
    it 'tracks dictionary mode from state' do
      expect(component).to be_visible

      allow(reader_state_reader).to receive(:mode).and_return(:read)
      expect(component).not_to be_visible
    end
  end

  describe '#render' do
    it 'does not render when dictionary mode is inactive' do
      allow(reader_state_reader).to receive(:mode).and_return(:read)
      component.render(surface, bounds)
      expect(terminal.writes).to be_empty
    end

    it 'renders nothing until a result is settled' do
      allow(reader_state_reader).to receive(:dictionary_result).and_return(nil)
      component.render(surface, bounds)
      expect(terminal.writes).to be_empty
    end

    it 'renders the definition card above the bar with the headword on the rule' do
      component.render(surface, bounds)

      rows = terminal.writes.map { |write| write[:row] }
      expect(rows).not_to include(bounds.height)
      expect(rows.max).to be < bounds.height

      text = rendered_rows.values.join("\n")
      expect(text).to include('revolution')
      expect(text).to include('de→en')
      expect(text).to include('forcible overthrow of a government')
    end

    it 'snaps flush to the left and caps its width on the right' do
      component.render(surface, bounds)
      writes = terminal.writes

      expect(writes.map { |write| write[:col] }).to all(eq(1))

      expected_width = [bounds.width, described_class::MAX_WIDTH].min
      expect(expected_width).to be < bounds.width

      bottom = writes.select { |write| write[:row] == bounds.height - 1 }
      raw = bottom.map { |write| write[:text] }.join
      expect(Shoko::Shared::Terminal::TextMetrics.visible_length(raw)).to eq(expected_width)
    end

    context 'when the reader centers its text and leaves an empty left margin' do
      let(:wide) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 200, height: 30) }
      let(:gap) { Shoko::Adapters::Ui::Components::BottomLeftPanel::SIDE_GAP }

      it 'shrinks the card into the margin instead of overlapping the text column' do
        component.content_left_edge = 60 # the book text starts at column 60
        component.render(surface, wide)

        bottom = terminal.writes.select { |write| write[:row] == wide.height - 1 }
        raw = bottom.map { |write| write[:text] }.join
        expect(Shoko::Shared::Terminal::TextMetrics.visible_length(raw)).to eq(60 - 1 - gap)
      end

      it 'wraps into a taller card in return for the width it gives up' do
        long = Shoko::Core::Models::DictionaryEntry.new(
          word: 'revolution',
          senses: Array.new(6) { |i| "sense #{i} " + (['a long winded definition clause'] * 8).join(' ') }
        )
        tall = Shoko::Core::Models::DictionaryResult.new(
          query: 'revolution', entries: [long], source_lang: 'de', target_lang: 'en', search_mode: :grouped
        )
        allow(reader_state_reader).to receive(:dictionary_result).and_return(tall)

        component.content_left_edge = 60
        component.render(surface, wide)
        constrained_top = terminal.writes.map { |write| write[:row] }.min

        terminal.reset!
        component.content_left_edge = nil
        component.render(surface, wide)
        natural_top = terminal.writes.map { |write| write[:row] }.min

        expect(constrained_top).to be < natural_top
      end
    end

    it 'renders fuzzy candidates with a pointer on the selected one' do
      matches = [
        Shoko::Core::Models::FuzzyMatch.new(word: 'revolutionary', similarity: 0.9),
        Shoko::Core::Models::FuzzyMatch.new(word: 'revolt', similarity: 0.7),
      ]
      allow(reader_state_reader).to receive(:dictionary_fuzzy_mode).and_return(true)
      allow(reader_state_reader).to receive(:dictionary_fuzzy_matches).and_return(matches)
      allow(reader_state_reader).to receive(:dictionary_selected_index).and_return(0)

      component.render(surface, bounds)

      pointer_row = rendered_rows.find { |_row, text| text.include?('▸') }
      expect(pointer_row).not_to be_nil
      expect(pointer_row.last).to include('revolutionary')
      expect(rendered_rows.values.join).to include('90%')
    end

    it 'maps clicks on fuzzy candidate rows to their index' do
      matches = [
        Shoko::Core::Models::FuzzyMatch.new(word: 'revolutionary', similarity: 0.9),
        Shoko::Core::Models::FuzzyMatch.new(word: 'revolt', similarity: 0.7),
      ]
      allow(reader_state_reader).to receive(:dictionary_fuzzy_mode).and_return(true)
      allow(reader_state_reader).to receive(:dictionary_fuzzy_matches).and_return(matches)

      component.render(surface, bounds)
      rule = terminal.writes.map { |write| write[:row] }.min

      expect(component.hit_test(3, rule + 1)).to eq(0) # first candidate
      expect(component.hit_test(3, rule + 2)).to eq(1) # second candidate
      expect(component.hit_test(3, rule)).to eq(:inside) # the rule
      expect(component.hit_test(3, rule - 1)).to eq(:outside) # the book above
    end

    it 'keeps the definition card inert to clicks but still dismissable from above' do
      component.render(surface, bounds) # entry (non-fuzzy) mode
      rule = terminal.writes.map { |write| write[:row] }.min

      expect(component.hit_test(3, rule + 1)).to eq(:inside)
      expect(component.hit_test(3, rule - 1)).to eq(:outside)
    end

    it 'shows a scroll affordance when the definition is taller than the card' do
      long = Shoko::Core::Models::DictionaryEntry.new(
        word: 'revolution',
        senses: Array.new(4) { |i| "sense #{i} " + (['a long winded definition clause'] * 8).join(' ') }
      )
      tall = Shoko::Core::Models::DictionaryResult.new(
        query: 'revolution', entries: [long], source_lang: 'de', target_lang: 'en', search_mode: :grouped
      )
      allow(reader_state_reader).to receive(:dictionary_result).and_return(tall)
      allow(reader_state_reader).to receive(:dictionary_selected_index).and_return(3)

      component.render(surface, bounds)
      expect(rendered_rows.values.join).to include('▲')
    end
  end
end
