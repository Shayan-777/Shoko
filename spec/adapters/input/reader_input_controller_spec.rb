# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::ReaderInputController do
  let(:reader_state_reader) { double('ReaderStateReader', mode: :read) }
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

  it 'builds EditOp insert payloads for dictionary character entry' do
    controller.activate_for_mode(:dictionary)
    controller.handle_key('x')

    expect(handler).to have_received(:handle_reader_intent).with(
      :edit_reader_dictionary_query,
      have_attributes(operation: :insert, text: 'x')
    )
  end

  it 'routes printable keys to the TOC filter in toc mode' do
    controller.activate_for_mode(:toc)
    controller.handle_key('x')

    expect(handler).to have_received(:handle_reader_intent).with(
      :edit_toc_filter,
      have_attributes(operation: :insert, text: 'x')
    )
  end

  it 'maps help mode keypresses to close_help_overlay' do
    controller.activate_for_mode(:help)
    controller.handle_key('x')

    expect(handler).to have_received(:handle_reader_intent).with(:close_help_overlay, nil)
  end

  it 'dispatches annotation_editor_confirm on Enter so the spell-suggestion popup can capture it' do
    controller.activate_for_mode(:annotation_editor)
    controller.handle_key("\r")

    expect(handler).to have_received(:handle_reader_intent).with(:annotation_editor_confirm, nil)
  end

  it 'uses Enter for a translator newline and Alt/Ctrl+Enter for submission' do
    controller.activate_for_mode(:translator)

    controller.handle_key("\r")
    controller.handle_key("\e\r")
    controller.handle_key("\e[13;5u")

    expect(handler).to have_received(:handle_reader_intent).with(:translator_confirm, nil)
    expect(handler).to have_received(:handle_reader_intent).with(:translator_submit, nil).twice
  end

  it 'maps modified Shift+Enter to an explicit translator newline edit' do
    controller.activate_for_mode(:translator)

    controller.handle_key("\e[13;2u")

    expect(handler).to have_received(:handle_reader_intent).with(
      :edit_translator,
      have_attributes(operation: :newline)
    )
  end
end
