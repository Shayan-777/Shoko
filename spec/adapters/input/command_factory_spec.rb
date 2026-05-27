# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::CommandFactory do
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

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
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
  let(:state) do
    bus = Shoko::Application::State::EventBus.new(logger: null_logger)
    Shoko::Application::State::ObserverStateStore.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities,
      schema_registry: schema_registry
    )
  end
  let(:menu_state_reader) do
    Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(state)
  end
  let(:menu_transient_store) do
    Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter.new(state)
  end
  let(:menu_session_mutator) do
    Shoko::Adapters::Runtime::SessionState::MenuSessionMutator.new(
      menu_session_store: Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(state),
      menu_transient_store: menu_transient_store
    )
  end
  let(:reader_session_mutator) { nil }
  let(:ctx) do
    Struct.new(:state, :menu_state_reader, :menu_session_mutator, :reader_session_mutator, :reader_state_reader).new(
      state,
      menu_state_reader,
      menu_session_mutator,
      reader_session_mutator,
      nil
    )
  end

  it 'builds navigation commands that update menu selection' do
    commands = described_class.navigation_commands(nil, :selected, ->(_context) { 3 })
    down_key = Shoko::Shared::KeyDefinitions::NAVIGATION[:down].first

    commands[down_key].call(ctx, nil)

    expect(state.get(%i[menu selected])).to eq(1)
  end

  it 'builds menu selection commands that invoke the handler' do
    handler = double('Handler', handle_menu_selection: nil)
    commands = described_class.menu_selection_commands
    key = Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].first

    commands[key].call(handler, nil)

    expect(handler).to have_received(:handle_menu_selection).once
  end

  it 'builds exit commands mapped to cancel keys' do
    commands = described_class.exit_commands(:exit_popup_menu)
    cancel_key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first
    expect(commands[cancel_key]).to eq(:exit_popup_menu)
  end

  it 'builds reader navigation commands for page movement' do
    commands = described_class.reader_navigation_commands
    next_key = Shoko::Shared::KeyDefinitions::READER[:next_page].first
    expect(commands[next_key]).to eq(:next_page)
  end

  it 'builds reader control commands for semantic bookmark action only' do
    commands = described_class.reader_control_commands
    bookmark_key = Shoko::Shared::KeyDefinitions::READER[:add_bookmark].first
    expect(commands[bookmark_key]).to eq(:add_bookmark)
    expect(commands.length).to eq(1)
  end

  it 'handles text input commands for insert, backspace, and delete' do
    commands = described_class.text_input_commands(:search_query, cursor_field: :search_cursor)

    commands[:__default__].call(ctx, 'a')
    expect(state.get(%i[menu search_query])).to eq('a')
    expect(state.get(%i[menu search_cursor])).to eq(1)

    state.update(%i[menu search_query] => 'ab', %i[menu search_cursor] => 2)
    backspace_key = Shoko::Shared::KeyDefinitions::ACTIONS[:backspace].first
    commands[backspace_key].call(ctx, nil)
    expect(state.get(%i[menu search_query])).to eq('a')
    expect(state.get(%i[menu search_cursor])).to eq(1)

    state.update(%i[menu search_query] => 'ab', %i[menu search_cursor] => 0)
    delete_key = Shoko::Shared::KeyDefinitions::ACTIONS[:delete].first
    commands[delete_key].call(ctx, nil)
    expect(state.get(%i[menu search_query])).to eq('b')
  end

  it 'uses explicit menu state reader/writer from context' do
    commands = described_class.text_input_commands(:search_query, cursor_field: :search_cursor)

    commands[:__default__].call(ctx, 'x')

    expect(state.get(%i[menu search_query])).to eq('x')
    expect(state.get(%i[menu search_cursor])).to eq(1)
  end

  it 'ignores non-printable input characters' do
    commands = described_class.text_input_commands(:search_query, cursor_field: :search_cursor)
    result = commands[:__default__].call(ctx, "\n")

    expect(result).to eq(:pass)
    expect(state.get(%i[menu search_query])).to eq('')
  end
end
