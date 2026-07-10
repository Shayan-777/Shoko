# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::ComponentFactory do
  let(:config_reader) { instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot, theme: :default) }
  subject(:factory) { described_class.new(config_reader: config_reader) }

  it 'builds popup components with the active theme-derived color mode' do
    popup_dark = factory.dictionary_popup
    expect(popup_dark.instance_variable_get(:@color_mode)).to eq(:dark)

    allow(config_reader).to receive(:theme).and_return(:gray)
    popup_light = factory.dictionary_popup
    expect(popup_light.instance_variable_get(:@color_mode)).to eq(:light)
  end

  it 'builds the dictionary lookup card using the active theme-derived color mode' do
    card_dark = factory.dictionary_lookup_popup(reader_state_reader: double('StateReader'))
    expect(card_dark.instance_variable_get(:@color_mode)).to eq(:dark)

    allow(config_reader).to receive(:theme).and_return(:sepia)
    card_light = factory.dictionary_lookup_popup(reader_state_reader: double('StateReader'))
    expect(card_light.instance_variable_get(:@color_mode)).to eq(:light)
  end

  it 'builds translator cards using the active theme-derived color mode' do
    card_dark = factory.translator_lookup_popup(reader_state_reader: double('StateReader'))
    expect(card_dark.instance_variable_get(:@color_mode)).to eq(:dark)

    allow(config_reader).to receive(:theme).and_return(:sepia)
    card_light = factory.translator_lookup_popup(reader_state_reader: double('StateReader'))
    expect(card_light.instance_variable_get(:@color_mode)).to eq(:light)
  end
end
