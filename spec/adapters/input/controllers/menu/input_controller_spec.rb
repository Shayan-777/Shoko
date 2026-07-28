# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::InputController do
  let(:menu_state_reader) { double('MenuStateReader', mode: :search) }
  let(:menu) { double('Menu', menu_state_reader: menu_state_reader) }
  let(:handler) { double('MenuIntentHandler', handle_menu_intent: :handled) }
  let(:factory) { Shoko::Adapters::Input::InputSystemFactoryAdapter.new }
  let(:key_classifier) { Shoko::Adapters::Input::KeyClassifierAdapter.new }

  subject(:controller) do
    described_class.new(
      menu,
      key_classifier: key_classifier,
      input_system_factory: factory,
      intent_handler: handler
    )
  end

  it 'builds EditOp insert payloads for browse search entry' do
    controller.handle_keys(['x'])

    expect(handler).to have_received(:handle_menu_intent).with(
      :edit_browse_search,
      have_attributes(operation: :insert, text: 'x')
    )
  end

  it 'dispatches semantic mode changes for dictionary search' do
    allow(menu_state_reader).to receive(:mode).and_return(:dictionary)
    controller.activate(:dictionary)

    controller.handle_keys(['/'])

    expect(handler).to have_received(:handle_menu_intent).with(
      :open_dictionary_mode,
      have_attributes(mode: :dictionary_search)
    )
  end

  it 'dispatches semantic annotation editor intents' do
    allow(menu_state_reader).to receive(:mode).and_return(:annotation_editor)
    controller.activate(:annotation_editor)

    controller.handle_keys(["\r"])

    expect(handler).to have_received(:handle_menu_intent).with(
      :edit_annotation_text,
      have_attributes(operation: :newline)
    )
  end

  it 'opens the download source selector from download mode' do
    allow(menu_state_reader).to receive(:mode).and_return(:download)
    controller.activate(:download)

    controller.handle_keys(["\t"])

    expect(handler).to have_received(:handle_menu_intent).with(:open_download_source_mode, nil)
  end

  it 'treats space as translator text input instead of submit' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator)
    controller.activate(:translator)

    controller.handle_keys([' '])

    expect(handler).to have_received(:handle_menu_intent).with(
      :edit_translator_input,
      have_attributes(operation: :insert, text: ' ')
    )
  end

  it 'types q in the translator instead of closing it' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator)
    controller.activate(:translator)

    controller.handle_keys(['q'])

    expect(handler).to have_received(:handle_menu_intent).with(
      :edit_translator_input, have_attributes(operation: :insert, text: 'q')
    )
    expect(handler).not_to have_received(:handle_menu_intent).with(:close_translator_mode, anything)
  end

  it 'closes the translator on Esc' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator)
    controller.activate(:translator)

    controller.handle_keys(["\e"])

    expect(handler).to have_received(:handle_menu_intent).with(:close_translator_mode, nil)
  end

  it 'uses Enter for a translator newline and Alt/Ctrl+Enter for submission' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator)
    controller.activate(:translator)

    controller.handle_keys(["\r", "\e\r", "\e[13;5u"])

    expect(handler).to have_received(:handle_menu_intent).with(:translator_activate_focus, nil)
    expect(handler).to have_received(:handle_menu_intent).with(:translator_submit, nil).twice
  end

  it 'types a picker filter and switches picker side with Tab' do
    allow(menu_state_reader).to receive(:mode).and_return(:translator_source_dropdown)
    controller.activate(:translator_source_dropdown)

    controller.handle_keys(['g', "\t"])

    expect(handler).to have_received(:handle_menu_intent).with(
      :edit_translator_language_query,
      have_attributes(operation: :insert, text: 'g')
    )
    expect(handler).to have_received(:handle_menu_intent).with(:translator_cycle_focus, nil)
  end

  it 'routes rss navigation keys through the rss reader intent set' do
    allow(menu_state_reader).to receive(:mode).and_return(:rss_reader)
    controller.activate(:rss_reader)

    controller.handle_keys(["\e[B", 'l', 's'])

    expect(handler).to have_received(:handle_menu_intent).with(
      :rss_reader_move_down,
      have_attributes(delta: 1)
    )
    expect(handler).to have_received(:handle_menu_intent).with(:rss_reader_focus_right, nil)
    expect(handler).to have_received(:handle_menu_intent).with(:rss_reader_sync, nil)
  end

  it 'keeps RSS list actions distinct from uppercase reading-selection actions' do
    allow(menu_state_reader).to receive(:mode).and_return(:rss_reader)
    controller.activate(:rss_reader)

    controller.handle_keys(%w[d D m M])

    expect(handler).to have_received(:handle_menu_intent).with(:rss_reader_remove_feed, nil)
    expect(handler).to have_received(:handle_menu_intent).with(:rss_reader_lookup_selection, nil)
    expect(handler).to have_received(:handle_menu_intent).with(:rss_reader_mark_starred, nil)
    expect(handler).to have_received(:handle_menu_intent).with(:rss_reader_annotate_selection, nil)
  end

  it 'uses rss filter text mode with a semantic close target' do
    allow(menu_state_reader).to receive(:mode).and_return(:rss_reader_filter)
    controller.activate(:rss_reader_filter)

    controller.handle_keys(['x', "\e"])

    expect(handler).to have_received(:handle_menu_intent).with(
      :edit_rss_filter,
      have_attributes(operation: :insert, text: 'x')
    )
    expect(handler).to have_received(:handle_menu_intent).with(
      :close_rss_reader_mode,
      have_attributes(mode: :rss_reader)
    )
  end
end
