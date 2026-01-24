# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Infrastructure::StateStore do
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
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
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
    store.update(%i[config view_mode] => :single)

    expect(events.length).to eq(1)
    expect(events.first.type).to eq(:state_changed)
  end

  it 'validates update values' do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    expect { store.update(%i[config view_mode] => :unknown) }.to raise_error(ArgumentError)
  end

  it 'persists config to disk' do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    store = described_class.new(bus, config_storage: config_storage, terminal_capabilities: terminal_capabilities)
    store.update(%i[config view_mode] => :single)
    store.save_config
    expect(File).to exist(config_file)
  end
end
