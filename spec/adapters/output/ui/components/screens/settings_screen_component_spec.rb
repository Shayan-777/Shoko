# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Screens::SettingsScreenComponent do
  def build_component_with(kitty_images:)
    component = described_class.new(nil, dependencies: nil)
    component.instance_variable_set(:@config_reader, double('ConfigReader', kitty_images: kitty_images))
    component
  end

  it 'marks kitty images disabled when config is false' do
    text, _color = build_component_with(kitty_images: false).send(:toggle_kitty_images_value)
    expect(text).to eq('Disabled')
  end

  it 'marks kitty images enabled when config is true' do
    text, _color = build_component_with(kitty_images: true).send(:toggle_kitty_images_value)
    expect(text).to eq('Enabled')
  end

  it 'marks kitty images disabled when config is nil' do
    text, _color = build_component_with(kitty_images: nil).send(:toggle_kitty_images_value)
    expect(text).to eq('Disabled')
  end
end
