# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe Shoko::Application::State::StateStore do
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

  def build_store(bus)
    described_class.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities,
      schema_registry: schema_registry
    )
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'emits state change events when updates occur' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    events = []
    subscriber = Class.new do
      def initialize(events)
        @events = events
      end

      def handle_event(event)
        @events << event
      end
    end
    bus.subscribe(subscriber.new(events), :state_changed)

    store = build_store(bus)
    change_set = store.update(%i[config view_mode] => :split)

    expect(events.length).to eq(1)
    expect(events.first.type).to eq(:state_changed)
    expect(change_set.size).to eq(1)
    expect(change_set.first.path).to eq(%i[config view_mode])
  end

  it 'validates update values' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = build_store(bus)
    expect { store.update(%i[config view_mode] => :unknown) }.to raise_error(ArgumentError)
  end

  it 'validates theme updates' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = build_store(bus)
    expect { store.update(%i[config theme] => :not_a_theme) }.to raise_error(ArgumentError)
  end

  it 'persists config to disk' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = build_store(bus)
    store.update(%i[config view_mode] => :single)
    store.save_config
    expect(File).to exist(config_file)
  end

  it 'allows event subscribers to read state during callbacks without deadlocking' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = build_store(bus)
    seen_modes = []

    subscriber = Class.new do
      def initialize(store, seen_modes)
        @store = store
        @seen_modes = seen_modes
      end

      def handle_event(event)
        return unless event.type == :state_changed

        @seen_modes << @store.get(%i[config view_mode])
      end
    end

    bus.subscribe(subscriber.new(store, seen_modes), :state_changed)

    Timeout.timeout(1) { store.update(%i[config view_mode] => :split) }
    expect(seen_modes).to include(:split)
  end

  it 'returns nil for no-op updates' do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    store = build_store(bus)

    expect(store.update(%i[config view_mode] => :single)).to be_nil
  end
end
