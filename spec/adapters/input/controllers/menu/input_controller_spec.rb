# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::InputController do
  let(:menu_state_reader) { double('MenuStateReader', mode: :search) }
  let(:menu) { double('Menu', menu_state_reader: menu_state_reader) }
  let(:handler) { double('MenuIntentHandler', handle_menu_intent: :handled) }
  let(:factory) { Shoko::Adapters::Input::InputSystemFactoryAdapter.new }
  let(:key_classifier) { Shoko::Adapters::Input::KeyClassifierAdapter.new(command_factory: Shoko::Adapters::Input::CommandFactory) }

  subject(:controller) do
    described_class.new(
      menu,
      key_classifier: key_classifier,
      input_system_factory: factory,
      intent_handler: handler
    )
  end

  it 'builds TextInput payloads for browse search entry' do
    controller.handle_keys(['x'])

    expect(handler).to have_received(:handle_menu_intent).with(
      :browse_insert_text,
      have_attributes(text: 'x')
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

    expect(handler).to have_received(:handle_menu_intent).with(:annotation_editor_newline, nil)
  end
end
