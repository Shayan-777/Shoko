# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::TranslatorLookupPopupComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  def translation_result(text: 'Hallo Welt', source: 'auto', target: 'de', detected: nil, error: nil)
    Shoko::Core::Models::TranslationResult.new(
      query: 'hello world', translated_text: text, source_lang: source, target_lang: target,
      detected_source_lang: detected, error_message: error
    )
  end

  let(:translator_state) do
    {
      mode: :translator,
      translator_result: translation_result,
      translator_query: 'hello world',
      translator_results_query: 'hello world',
      translator_source_lang: 'auto',
      translator_target_lang: 'de',
      translator_languages: [{ code: 'en', name: 'English' }, { code: 'de', name: 'German' }],
      translator_picker_side: nil,
      translator_picker_query: '',
      translator_picker_index: 0,
      translator_scroll: 0,
      translator_cursor: 11,
    }
  end
  let(:reader_state_reader) { instance_double('ReaderStateReader', **translator_state) }

  subject(:component) { described_class.new(reader_state_reader: reader_state_reader) }

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 100, height: 22) }
  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }

  before { terminal.reset! }

  def rendered_rows
    terminal.writes.group_by { |write| write[:row] }.transform_values do |writes|
      strip_ansi(writes.map { |write| write[:text] }.join)
    end
  end

  describe '#visible?' do
    it 'tracks translator mode from state' do
      expect(component).to be_visible

      allow(reader_state_reader).to receive(:mode).and_return(:read)
      expect(component).not_to be_visible
    end
  end

  describe '#render editor mode' do
    it 'does not render when translator mode is inactive' do
      allow(reader_state_reader).to receive(:mode).and_return(:read)
      component.render(surface, bounds)
      expect(terminal.writes).to be_empty
    end

    it 'shows a roomy source well with a placeholder before anything is typed' do
      allow(reader_state_reader).to receive(:translator_query).and_return('')
      allow(reader_state_reader).to receive(:translator_results_query).and_return('')
      allow(reader_state_reader).to receive(:translator_result).and_return(nil)
      component.render(surface, bounds)

      text = rendered_rows.values.join("\n")
      expect(text).to include('Type or paste text to translate')
      expect(text).to include('↵ to translate') # the empty translation pane invites the action
    end

    it 'lays the source editor over a labeled divider and the translation' do
      component.render(surface, bounds)

      rows = terminal.writes.map { |write| write[:row] }
      expect(rows.max).to be < bounds.height # never paints over the status bar row

      text = rendered_rows.values.join("\n")
      expect(text).to include('hello world')         # the source, in its well
      expect(text).to include('↓ German')            # the labeled divider names the target
      expect(text).to include('Hallo Welt')          # the translation
      expect(text).to include('AUTO')
      expect(text).to include('DE')
    end

    it 'draws a blinking thin-stripe caret in the source well' do
      component.render(surface, bounds)
      text = rendered_rows.values.join
      caret_writes = terminal.writes.select { |write| write[:text].include?(palette::TRANS_CARET_FG) }
      expect(caret_writes).not_to be_empty       # the caret style is emitted
      expect(text).to include('▏')               # rendered as the thin stripe glyph
    end

    it 'wraps hard newlines (Shift/Alt+Enter) onto separate source rows' do
      list = "milk\neggs\nbread"
      allow(reader_state_reader).to receive(:translator_query).and_return(list)
      allow(reader_state_reader).to receive(:translator_cursor).and_return(0)
      component.render(surface, bounds)

      row_of = ->(word) { rendered_rows.find { |_r, text| text.include?(word) }&.first }
      rows = [row_of.call('milk'), row_of.call('eggs'), row_of.call('bread')]
      expect(rows).to all(be_truthy)        # each item rendered
      expect(rows.uniq.length).to eq(3)     # on three separate rows
    end

    it 'wraps a multi-sentence source across several rows of the well' do
      long = 'The quick brown fox jumps over the lazy dog and then keeps running into the night.'
      allow(reader_state_reader).to receive(:translator_query).and_return(long)
      allow(reader_state_reader).to receive(:translator_cursor).and_return(long.length)
      component.render(surface, bounds)

      row_for = ->(word) { rendered_rows.find { |_r, text| text.include?(word) }&.first }
      # An early word and a late word land on different rows — the prose wrapped.
      expect(row_for.call('quick')).not_to be_nil
      expect(row_for.call('night.')).not_to be_nil
      expect(row_for.call('quick')).not_to eq(row_for.call('night.'))
    end

    it 'shows the detected language when the source was auto-detected' do
      allow(reader_state_reader).to receive(:translator_result).and_return(translation_result(detected: 'en'))
      component.render(surface, bounds)
      expect(rendered_rows.values.join("\n")).to include('Detected: English')
    end

    it 'surfaces a translation failure' do
      allow(reader_state_reader).to receive(:translator_result)
        .and_return(translation_result(text: '', error: 'connection refused'))
      component.render(surface, bounds)
      expect(rendered_rows.values.join("\n")).to include('connection refused')
    end

    it 'snaps flush to the left and caps its width on the right' do
      component.render(surface, bounds)

      expect(terminal.writes.map { |write| write[:col] }).to all(eq(1))

      expected_width = [bounds.width, described_class::MAX_WIDTH].min
      bottom = terminal.writes.select { |write| write[:row] == bounds.height - 1 }
      raw = bottom.map { |write| write[:text] }.join
      expect(Shoko::Shared::Terminal::TextMetrics.visible_length(raw)).to eq(expected_width)
    end

    it 'shrinks into the empty left margin a centered text column leaves' do
      wide = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 200, height: 30)
      gap = Shoko::Adapters::Ui::Components::BottomLeftPanel::SIDE_GAP

      component.content_left_edge = 60
      component.render(surface, wide)

      bottom = terminal.writes.select { |write| write[:row] == wide.height - 1 }
      raw = bottom.map { |write| write[:text] }.join
      expect(Shoko::Shared::Terminal::TextMetrics.visible_length(raw)).to eq(60 - 1 - gap)
    end
  end

  describe '#render picker mode' do
    before do
      allow(reader_state_reader).to receive(:translator_picker_side).and_return(:target)
      allow(reader_state_reader).to receive(:translator_picker_index).and_return(1)
    end

    it 'renders the language list with a pointer on the selected language' do
      component.render(surface, bounds)

      pointer_row = rendered_rows.find { |_row, text| text.include?('▸') }
      expect(pointer_row).not_to be_nil
      expect(pointer_row.last).to include('German')
    end

    it 'marks the current target language and names both sides on the rule' do
      # Select English so the current target (German) shows its ● marker rather
      # than the selection pointer (which would otherwise take precedence).
      allow(reader_state_reader).to receive(:translator_picker_index).and_return(0)
      component.render(surface, bounds)
      text = rendered_rows.values.join("\n")

      expect(text).to include('Source')
      expect(text).to include('Target')
      expect(text).to include('●') # current-language marker (target is 'de')
    end

    it 'filters the list to the picker query and echoes the filter on the rule' do
      allow(reader_state_reader).to receive(:translator_picker_query).and_return('eng')
      allow(reader_state_reader).to receive(:translator_picker_index).and_return(0)
      component.render(surface, bounds)

      rule = rendered_rows.values.find { |t| t.include?('Source') }
      expect(rule).to include('eng') # the live filter rides the picker header

      body = rendered_rows.reject { |_row, text| text.include?('Source') }.values.join("\n")
      expect(body).to include('English')
      expect(body).not_to include('German')
    end
  end
end
