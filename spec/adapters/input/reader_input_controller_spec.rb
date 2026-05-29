# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::ReaderInputController do
  let(:reader_state_reader) { double('ReaderStateReader', sidebar_visible?: false, sidebar_active_tab: :toc, mode: :read) }
  let(:handler) { double('ReaderIntentHandler', handle_reader_intent: :handled) }

  subject(:controller) do
    described_class.new(
      reader_state_reader: reader_state_reader
    )
  end

  before do
    controller.setup_input_dispatcher(handler)
  end

  it 'dispatches semantic reader intents for read mode navigation' do
    controller.handle_key('j')

    expect(handler).to have_received(:handle_reader_intent).with(:scroll_down, nil)
  end

  it 'switches to sidebar intents when the sidebar is visible' do
    allow(reader_state_reader).to receive(:sidebar_visible?).and_return(true)

    controller.handle_key('j')

    expect(handler).to have_received(:handle_reader_intent).with(
      :sidebar_move_down,
      have_attributes(delta: 1)
    )
  end

  it 'builds EditOp insert payloads for dictionary character entry' do
    controller.activate_for_mode(:dictionary)
    controller.handle_key('x')

    expect(handler).to have_received(:handle_reader_intent).with(
      :edit_reader_dictionary_query,
      have_attributes(operation: :insert, text: 'x')
    )
  end

  it 'maps help mode keypresses to close_help_overlay' do
    controller.activate_for_mode(:help)
    controller.handle_key('x')

    expect(handler).to have_received(:handle_reader_intent).with(:close_help_overlay, nil)
  end
end
