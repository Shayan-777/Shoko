# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::CommandFactory do
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

  let(:state) do
    bus = Shoko::Adapters::State::EventBus.new(logger: null_logger)
    Shoko::Adapters::State::ObserverStateStore.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities
    )
  end
  let(:menu_state_reader) { Shoko::Adapters::State::MenuStateReaderAdapter.new(state) }
  let(:menu_state_writer) { Shoko::Adapters::State::MenuStateWriterAdapter.new(state) }
  let(:deps) do
    dep = instance_double('Dependencies')
    allow(dep).to receive(:resolve).with(:menu_state_reader).and_return(menu_state_reader)
    allow(dep).to receive(:resolve).with(:menu_state_writer).and_return(menu_state_writer)
    allow(dep).to receive(:resolve).with(:state_writer).and_return(nil)
    dep
  end
  let(:ctx) do
    Struct.new(:state, :deps).new(state, deps)
  end
  let(:ctx_with_dependencies) do
    Struct.new(:state, :dependencies).new(state, deps)
  end

  it 'builds navigation commands that update menu selection' do
    commands = described_class.navigation_commands(nil, :selected, ->(_context) { 3 })
    down_key = Shoko::Adapters::Input::KeyDefinitions::NAVIGATION[:down].first

    commands[down_key].call(ctx, nil)

    expect(state.get(%i[menu selected])).to eq(1)
  end

  it 'builds menu selection commands that invoke the handler' do
    handler = double('Handler', handle_menu_selection: nil)
    commands = described_class.menu_selection_commands
    key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:confirm].first

    commands[key].call(handler, nil)

    expect(handler).to have_received(:handle_menu_selection).once
  end

  it 'builds exit commands mapped to cancel keys' do
    commands = described_class.exit_commands(:exit_popup_menu)
    cancel_key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:cancel].first
    expect(commands[cancel_key]).to eq(:exit_popup_menu)
  end

  it 'builds reader navigation commands for page movement' do
    commands = described_class.reader_navigation_commands
    next_key = Shoko::Adapters::Input::KeyDefinitions::READER[:next_page].first
    expect(commands[next_key]).to eq(:next_page)
  end

  it 'builds reader control commands for quit action' do
    commands = described_class.reader_control_commands
    quit_key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:quit].first
    expect(commands[quit_key]).to eq(:quit_to_menu)
  end

  it 'handles text input commands for insert, backspace, and delete' do
    commands = described_class.text_input_commands(:search_query, nil, cursor_field: :search_cursor)

    commands[:__default__].call(ctx, 'a')
    expect(state.get(%i[menu search_query])).to eq('a')
    expect(state.get(%i[menu search_cursor])).to eq(1)

    state.update(%i[menu search_query] => 'ab', %i[menu search_cursor] => 2)
    backspace_key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:backspace].first
    commands[backspace_key].call(ctx, nil)
    expect(state.get(%i[menu search_query])).to eq('a')
    expect(state.get(%i[menu search_cursor])).to eq(1)

    state.update(%i[menu search_query] => 'ab', %i[menu search_cursor] => 0)
    delete_key = Shoko::Adapters::Input::KeyDefinitions::ACTIONS[:delete].first
    commands[delete_key].call(ctx, nil)
    expect(state.get(%i[menu search_query])).to eq('b')
  end

  it 'resolves menu state adapters via dependencies' do
    commands = described_class.text_input_commands(:search_query, nil, cursor_field: :search_cursor)

    commands[:__default__].call(ctx_with_dependencies, 'x')

    expect(state.get(%i[menu search_query])).to eq('x')
    expect(state.get(%i[menu search_cursor])).to eq(1)
  end

  it 'ignores non-printable input characters' do
    commands = described_class.text_input_commands(:search_query, nil, cursor_field: :search_cursor)
    result = commands[:__default__].call(ctx, "\n")

    expect(result).to eq(:pass)
    expect(state.get(%i[menu search_query])).to eq('')
  end
end
