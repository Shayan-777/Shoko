# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe Shoko::Application::Infrastructure::ObserverStateStore do
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }
  let(:terminal_capabilities) { Shoko::Core::Services::DefaultTerminalCapabilities.new }
  let(:config_dir) { @tmpdir }
  let(:config_file) { File.join(@tmpdir, 'config.json') }
  let(:config_storage) do
    storage = Object.new
    dir = config_dir
    file = config_file
    storage.define_singleton_method(:config_dir) { dir }
    storage.define_singleton_method(:config_file) { file }
    storage.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(dir) }
    storage.define_singleton_method(:atomic_write) do |path, data|
      File.write(path, data)
    end
    storage.define_singleton_method(:read_file) do |path|
      File.exist?(path) ? File.read(path) : nil
    end
    storage
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'notifies observers for specific paths' do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'notifies observers for parent paths' do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'notifies a path observer only once when using set' do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.set(%i[reader mode], :help)

    expect(observer).to have_received(:state_changed).once
  end

  it 'does not notify observers when set is a no-op' do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.set(%i[reader mode], :read)

    expect(observer).not_to have_received(:state_changed)
  end

  it 'loads config values even when optional symbol fields are nil' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, JSON.pretty_generate({ view_mode: 'single', dictionary_backend: nil }))

    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)

    expect(store.get(%i[config view_mode])).to eq(:single)
    expect(store.get(%i[config dictionary_backend])).to be_nil
  end

  it 'keeps valid config values when others are invalid' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, JSON.pretty_generate({ view_mode: 'single', kitty_images: 'nope' }))

    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)

    expect(store.get(%i[config view_mode])).to eq(:single)
    expect([true, false]).to include(store.get(%i[config kitty_images]))
  end
end
