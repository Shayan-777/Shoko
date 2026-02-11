# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Commands::MenuCommand do
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

  def create_state
    bus = Shoko::Adapters::State::EventBus.new(logger: null_logger)
    Shoko::Adapters::State::ObserverStateStore.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities
    )
  end

  it 'updates menu selection indices' do
    state = create_state
    menu_state_reader = Shoko::Adapters::State::MenuStateReaderAdapter.new(state)
    menu_state_writer = Shoko::Adapters::State::MenuStateWriterAdapter.new(state)
    context = Struct.new(:menu_state_reader, :menu_state_writer, :main_menu_component).new(
      menu_state_reader,
      menu_state_writer,
      nil
    )

    command = described_class.new(:menu_down)
    result = command.execute(context, key: "\n", triggered_by: :input)
    expect(result).to eq(:handled)
    expect(state.get(%i[menu selected])).to eq(1)
  end

  it 'invokes settings actions based on selection' do
    state = create_state
    state.update(%i[menu settings_selected] => 1)
    menu_state_reader = Shoko::Adapters::State::MenuStateReaderAdapter.new(state)
    menu_state_writer = Shoko::Adapters::State::MenuStateWriterAdapter.new(state)

    context = Class.new do
      attr_reader :menu_state_reader, :menu_state_writer, :called

      def initialize(menu_state_reader, menu_state_writer)
        @menu_state_reader = menu_state_reader
        @menu_state_writer = menu_state_writer
        @called = false
      end

      def main_menu_component
        nil
      end

      def toggle_view_mode
        @called = true
      end
    end.new(menu_state_reader, menu_state_writer)

    command = described_class.new(:settings_select)
    command.execute(context, key: "\n", triggered_by: :input)
    expect(context.called).to be(true)
  end
end
