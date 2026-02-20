# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

RSpec.describe Shoko::Adapters::Runtime::SessionState::StateStore do
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

  it 'emits state change events when updates occur' do
    bus = Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger)
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

    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    store.update(%i[config view_mode] => :split)

    expect(events.length).to eq(1)
    expect(events.first.type).to eq(:state_changed)
  end

  it 'validates update values' do
    bus = Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    expect { store.update(%i[config view_mode] => :unknown) }.to raise_error(ArgumentError)
  end

  it 'persists config to disk' do
    bus = Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    store.update(%i[config view_mode] => :single)
    store.save_config
    expect(File).to exist(config_file)
  end

  it 'allows event subscribers to read state during callbacks without deadlocking' do
    bus = Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
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
end
