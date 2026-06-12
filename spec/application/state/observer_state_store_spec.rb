# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe Shoko::Application::State::ObserverStateStore do
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }
  let(:terminal_capabilities) { Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new }
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
    storage.define_singleton_method(:file_exist?) do |path|
      File.exist?(path)
    end
    storage
  end
  let(:schema_registry) do
    Shoko::Application::State::SchemaRegistry.new
      .register(Shoko::Core::Reading::Schema)
      .register(Shoko::Application::State::Schema::ReaderProcess)
      .register(Shoko::Application::State::Schema::ReaderPagination)
      .register(Shoko::Application::State::Schema::ReaderView)
      .register(Shoko::Application::State::Schema::MenuProcess)
      .register(Shoko::Application::State::Schema::MenuTransient)
      .register(Shoko::Application::State::Schema::Config)
      .register(Shoko::Application::State::Schema::UiGlobals)
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'notifies observers for specific paths' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'notifies observers for parent paths' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'returns a change set for committed updates' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    change_set = store.update(
      %i[reader mode] => :help,
      %i[config view_mode] => :split
    )

    expect(change_set).to be_a(Shoko::Application::State::StateStore::ChangeSet)
    expect(change_set.size).to eq(2)
    expect(change_set.map(&:path)).to contain_exactly(%i[reader mode], %i[config view_mode])
  end

  it 'notifies a path observer only once when using set' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.set(%i[reader mode], :help)

    expect(observer).to have_received(:state_changed).once
  end

  it 'does not notify observers when set is a no-op' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.set(%i[reader mode], :read)

    expect(observer).not_to have_received(:state_changed)
  end

  it 'notifies parent observers once per changed path in a multi-path update' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader])
    store.update(
      %i[reader mode] => :help,
      %i[reader annotations_overlay_selected] => 3
    )

    expect(observer).to have_received(:state_changed).with(%i[reader mode], :read, :help).once
    expect(observer).to have_received(:state_changed).with(%i[reader annotations_overlay_selected], 0, 3).once
  end

  it 'does not notify the same observer twice for a single change when registered on overlapping paths' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader], %i[reader mode])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).with(%i[reader mode], :read, :help).once
  end

  it 'does not notify the same observer twice when registered globally and on a specific path' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer)
    store.add_observer(observer, %i[reader mode])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).with(%i[reader mode], :read, :help).once
  end

  it 'loads config values even when optional symbol fields are nil' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, JSON.pretty_generate({ view_mode: 'single', dictionary_backend: nil }))

    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    expect(store.get(%i[config view_mode])).to eq(:single)
    expect(store.get(%i[config dictionary_backend])).to be_nil
  end

  it 'keeps valid config values when others are invalid' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, JSON.pretty_generate({ view_mode: 'single', kitty_images: 'nope' }))

    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    expect(store.get(%i[config view_mode])).to eq(:single)
    expect([true, false]).to include(store.get(%i[config kitty_images]))
  end

  it 'normalizes legacy theme aliases when loading config' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, JSON.pretty_generate({ theme: 'dark' }))

    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    expect(store.get(%i[config theme])).to eq(:default)
  end

  it 'falls back to default theme when persisted theme is invalid' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, JSON.pretty_generate({ theme: 'bad-theme' }))

    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    expect(store.get(%i[config theme])).to eq(:default)
  end

  it 'starts with defaults instead of crashing when the config file is corrupt JSON' do
    FileUtils.mkdir_p(File.dirname(config_file))
    File.write(config_file, '{ corrupt json !!!')

    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = nil
    expect do
      store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
    end.not_to raise_error

    expect(store.get(%i[config theme])).to eq(:default)
    expect(store.get(%i[config view_mode])).to eq(:single)
  end

  it 'isolates a failing observer: the update commits and other observers are still notified' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    failing = double('FailingObserver')
    allow(failing).to receive(:state_changed).and_raise(NoMethodError, 'observer bug')
    healthy = double('HealthyObserver')
    allow(healthy).to receive(:state_changed)

    store.add_observer(failing, %i[reader mode])
    store.add_observer(healthy, %i[reader mode])

    change_set = nil
    expect { change_set = store.update(%i[reader mode] => :help) }.not_to raise_error

    expect(change_set).not_to be_nil
    expect(store.get(%i[reader mode])).to eq(:help)
    expect(healthy).to have_received(:state_changed).at_least(:once)
  end

  it 'tolerates an observer without state_changed: the update still commits' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)

    store.add_observer(Object.new, %i[reader mode])

    expect { store.update(%i[reader mode] => :help) }.not_to raise_error
    expect(store.get(%i[reader mode])).to eq(:help)
  end
end
