# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::State::StateStore do
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

  def build_store
    described_class.new(
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

  it 'returns the change set for committed updates' do
    store = build_store
    change_set = store.update(%i[config view_mode] => :split)

    expect(change_set.size).to eq(1)
    expect(change_set.first.path).to eq(%i[config view_mode])
    expect(change_set.first.new_value).to eq(:split)
  end

  it 'validates update values' do
    store = build_store
    expect { store.update(%i[config view_mode] => :unknown) }.to raise_error(ArgumentError)
  end

  it 'validates theme updates' do
    store = build_store
    expect { store.update(%i[config theme] => :not_a_theme) }.to raise_error(ArgumentError)
  end

  it 'persists config to disk' do
    store = build_store
    store.update(%i[config view_mode] => :single)
    store.save_config
    expect(File).to exist(config_file)
  end

  it 'returns nil for no-op updates' do
    store = build_store

    expect(store.update(%i[config view_mode] => :single)).to be_nil
  end

  it 'dispatches action objects by calling #apply with itself' do
    store = build_store
    action = Class.new do
      attr_reader :applied_to

      def apply(target)
        @applied_to = target
      end
    end.new

    store.dispatch(action)

    expect(action.applied_to).to be(store)
  end

  it 'fails fast when dispatching an object without #apply' do
    store = build_store

    expect { store.dispatch(Object.new) }.to raise_error(NoMethodError, /apply/)
  end

  it 'propagates validator errors from inside an action unmasked' do
    store = build_store
    action = Class.new do
      def apply(target)
        target.update(%i[config view_mode] => :unknown)
      end
    end.new

    expect { store.dispatch(action) }.to raise_error(ArgumentError, 'invalid view_mode')
  end
end
