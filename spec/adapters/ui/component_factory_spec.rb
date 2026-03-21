# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::ComponentFactory do
  let(:config_reader) { instance_double('ConfigReader', theme: :default) }
  subject(:factory) { described_class.new(config_reader: config_reader) }

  it 'builds popup components with the active theme-derived color mode' do
    popup_dark = factory.dictionary_popup
    expect(popup_dark.instance_variable_get(:@color_mode)).to eq(:dark)

    allow(config_reader).to receive(:theme).and_return(:gray)
    popup_light = factory.dictionary_popup
    expect(popup_light.instance_variable_get(:@color_mode)).to eq(:light)
  end

  it 'builds dictionary panels using the active theme-derived color mode' do
    panel_dark = factory.dictionary_panel(double('StateReader'))
    expect(panel_dark.instance_variable_get(:@color_mode)).to eq(:dark)

    allow(config_reader).to receive(:theme).and_return(:sepia)
    panel_light = factory.dictionary_panel(double('StateReader'))
    expect(panel_light.instance_variable_get(:@color_mode)).to eq(:light)
  end

  it 'builds translation popups using the active theme-derived color mode' do
    popup_dark = factory.translation_popup
    expect(popup_dark.instance_variable_get(:@color_mode)).to eq(:dark)

    allow(config_reader).to receive(:theme).and_return(:sepia)
    popup_light = factory.translation_popup
    expect(popup_light.instance_variable_get(:@color_mode)).to eq(:light)
  end
end
