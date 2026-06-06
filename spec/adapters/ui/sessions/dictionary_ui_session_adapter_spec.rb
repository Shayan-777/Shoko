# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Sessions::DictionaryUiSessionAdapter do
  let(:lookup_popup) do
    instance_double('DictionaryLookupPopup', visible?: true, update_color_mode: nil, render: nil)
  end
  let(:setup_popup) do
    instance_double('DictionaryPopup',
                    hide: nil,
                    visible?: false,
                    update_color_mode: nil,
                    insert_char: { type: :setup_change, value: 'x' },
                    backspace: nil,
                    confirm: nil,
                    tab: nil,
                    swap_languages: nil,
                    scroll_up_action: { type: :setup_select },
                    scroll_down_action: { type: :setup_select },
                    show_setup: nil,
                    update_setup: nil,
                    setup_mode?: true)
  end
  let(:reader_state_reader) do
    instance_double('ReaderStateReader',
                    dictionary_lookup_popup: lookup_popup,
                    dictionary_popup: setup_popup,
                    dictionary_result: nil,
                    mode: :dictionary)
  end
  let(:reader_session_mutator) { instance_double('ReaderSessionMutator', update_reader: nil) }
  let(:ui_component_factory) do
    instance_double('UIFactory', dictionary_lookup_popup: lookup_popup, dictionary_popup: setup_popup)
  end
  let(:logger) { instance_double('Logger', error: nil) }
  let(:result) { instance_double('DictionaryResult', query: 'haus') }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      ui_component_factory: ui_component_factory,
      logger: logger
    )
  end

  it 'opens the definition card and resets lookup state' do
    outcome = session.open

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:dictionary_opened)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      hash_including(
        dictionary_lookup_popup: lookup_popup,
        dictionary_popup: nil,
        dictionary_visible: true,
        mode: :dictionary,
        popup_menu: nil,
        dictionary_query: '',
        dictionary_results_query: '',
        dictionary_setup_active: false
      )
    )
  end

  it 'applies a lookup result to view-state' do
    outcome = session.apply_result(result)

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:dictionary_result_applied)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      hash_including(
        dictionary_result: result,
        dictionary_results_query: 'haus',
        dictionary_entry_index: 0,
        dictionary_selected_index: 0,
        dictionary_fuzzy_mode: false,
        dictionary_setup_active: false,
        mode: :dictionary
      )
    )
  end

  it 'applies fuzzy matches and resets the selected index' do
    matches = [double('FuzzyMatch')]
    outcome = session.apply_fuzzy(matches)

    expect(outcome.ok).to be(true)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      hash_including(dictionary_fuzzy_mode: true, dictionary_fuzzy_matches: matches, dictionary_selected_index: 0)
    )
  end

  it 'closes and clears dictionary state' do
    outcome = session.close

    expect(outcome.ok).to be(true)
    expect(outcome.code).to eq(:dictionary_closed)
    expect(setup_popup).to have_received(:hide)
    expect(reader_session_mutator).to have_received(:update_reader).with(
      hash_including(
        dictionary_lookup_popup: nil,
        dictionary_popup: nil,
        dictionary_visible: false,
        dictionary_result: nil,
        mode: :read
      )
    )
  end

  it 'reports visibility from the reader mode' do
    allow(reader_state_reader).to receive(:mode).and_return(:dictionary)
    expect(session).to be_visible

    allow(reader_state_reader).to receive(:mode).and_return(:read)
    expect(session).not_to be_visible
  end

  it 'dispatches setup input to the wizard popup and carries its event' do
    allow(setup_popup).to receive(:visible?).and_return(true)

    outcome = session.insert_char('x')

    expect(outcome.ok).to be(true)
    expect(outcome.payload).to eq(type: :setup_change, value: 'x')
    expect(setup_popup).to have_received(:insert_char).with('x')
  end

  it 'ignores setup input when no wizard popup is visible' do
    allow(setup_popup).to receive(:visible?).and_return(false)

    outcome = nil
    expect { outcome = session.insert_char('t') }.not_to raise_error

    expect(outcome.ok).to be(false)
    expect(outcome.status).to eq(:ignored)
  end

  it 'shows and updates setup state through the wizard popup' do
    show_outcome = session.show_setup(stage: :prompt_source, query: 'haus')
    update_outcome = session.update_setup(stage: :prompt_target, input_value: 'en')

    expect(show_outcome.ok).to be(true)
    expect(update_outcome.ok).to be(true)
    expect(setup_popup).to have_received(:show_setup).with(stage: :prompt_source, query: 'haus')
    expect(setup_popup).to have_received(:update_setup).with(stage: :prompt_target, input_value: 'en')
  end

  it 'refreshes both surfaces theme mode' do
    session.refresh_theme(color_mode: :light)

    expect(lookup_popup).to have_received(:update_color_mode).with(:light)
    expect(setup_popup).to have_received(:update_color_mode).with(:light)
  end

  it 'logs and returns a failed outcome when opening cannot build a popup' do
    allow(reader_state_reader).to receive(:dictionary_lookup_popup).and_return(nil)
    allow(ui_component_factory).to receive(:dictionary_lookup_popup).and_raise(RuntimeError, 'boom')

    outcome = session.open

    expect(outcome.ok).to be(false)
    expect(outcome.code).to eq(:dictionary_lookup_unavailable)
  end
end
