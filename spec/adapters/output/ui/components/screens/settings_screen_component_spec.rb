# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Screens::SettingsScreenComponent do
  it 'marks kitty images disabled when config is false' do
    component = described_class.new(double('state'), nil, dependencies: nil)
    component.instance_variable_set(:@config_reader, double('ConfigReader', kitty_images: false))

    text, _color = component.send(:toggle_kitty_images_value)
    expect(text).to eq('Disabled')
  end
end
