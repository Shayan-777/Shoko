# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Sessions::DictionaryUiSessionAdapter do
  let(:panel) { instance_double('DictionaryPanel', show: nil, hide: nil, visible?: false, result: nil) }
  let(:popup) do
    instance_double('DictionaryPopup',
                    show: nil,
                    hide: nil,
                    visible?: false,
                    result: nil,
                    insert_char: { type: :setup_change, value: 'x' },
                    backspace: nil,
                    confirm: nil,
                    cancel: { type: :close },
                    tab: nil,
                    swap_languages: nil,
                    scroll_up_action: { type: :scroll },
                    scroll_down_action: { type: :scroll },
                    show_setup: nil,
                    update_setup: nil,
                    setup_mode?: false)
  end
  let(:reader_state_reader) { instance_double('ReaderStateReader', dictionary_panel: panel, dictionary_popup: popup) }
  let(:state_writer) { instance_double('ReaderStateWriter', update_reader: nil) }
  let(:ui_component_factory) { instance_double('UIFactory', dictionary_panel: panel, dictionary_popup: popup) }
  let(:result) { instance_double('DictionaryResult', query: 'haus') }

  subject(:session) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      state_writer: state_writer,
      ui_component_factory: ui_component_factory
    )
  end

  it 'shows popup and updates reader state' do
    expect(session.show_popup(result)).to be(true)
    expect(popup).to have_received(:show).with(result)
    expect(state_writer).to have_received(:update_reader).with(
      dictionary_panel: nil,
      dictionary_popup: popup,
      dictionary_visible: true,
      mode: :dictionary,
      popup_menu: nil
    )
  end

  it 'closes active dictionary UI and clears state' do
    expect(session.close).to be(true)
    expect(panel).to have_received(:hide)
    expect(popup).to have_received(:hide)
    expect(state_writer).to have_received(:update_reader).with(
      dictionary_panel: nil,
      dictionary_popup: nil,
      dictionary_visible: false,
      mode: :read
    )
  end

  it 'delegates input intents to active component' do
    allow(panel).to receive(:visible?).and_return(false)
    allow(popup).to receive(:visible?).and_return(true)

    expect(session.insert_char('x')).to eq(type: :setup_change, value: 'x')
    expect(popup).to have_received(:insert_char).with('x')
  end

  it 'updates setup state through popup' do
    expect(session.show_setup(stage: :prompt_source, query: 'haus')).to be(true)
    expect(session.update_setup(stage: :prompt_target, input_value: 'en')).to be(true)
    expect(popup).to have_received(:show_setup).with(stage: :prompt_source, query: 'haus')
    expect(popup).to have_received(:update_setup).with(stage: :prompt_target, input_value: 'en')
  end
end
