# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe Shoko::Application::Infrastructure::ObserverStateStore do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'notifies observers for specific paths' do
    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'notifies observers for parent paths' do
    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'loads config values even when optional symbol fields are nil' do
    config_path = described_class.config_file
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, JSON.pretty_generate({ view_mode: 'single', dictionary_backend: nil }))

    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)

    expect(store.get(%i[config view_mode])).to eq(:single)
    expect(store.get(%i[config dictionary_backend])).to be_nil
  end

  it 'keeps valid config values when others are invalid' do
    config_path = described_class.config_file
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, JSON.pretty_generate({ view_mode: 'single', kitty_images: 'nope' }))

    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)

    expect(store.get(%i[config view_mode])).to eq(:single)
    expect([true, false]).to include(store.get(%i[config kitty_images]))
  end
end
