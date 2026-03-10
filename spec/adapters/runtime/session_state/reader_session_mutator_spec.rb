# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator do
  let(:terminal_capabilities) { Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new }
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }
  let(:config_storage) do
    dir = @tmpdir
    file = File.join(@tmpdir, 'config.json')
    storage = Object.new
    storage.define_singleton_method(:config_dir) { dir }
    storage.define_singleton_method(:config_file) { file }
    storage.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(dir) }
    storage.define_singleton_method(:atomic_write) { |_path, _data| }
    storage.define_singleton_method(:read_file) { |_path| nil }
    storage
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  let(:state_store) do
    bus = Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger)
    Shoko::Adapters::Runtime::SessionState::StateStore.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities
    )
  end
  let(:reader_session_store) do
    Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(state_store)
  end
  let(:app_config_store) do
    Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(state_store)
  end

  subject(:mutator) do
    described_class.new(
      reader_session_store: reader_session_store,
      app_config_store: app_config_store
    )
  end

  it 'writes reader popup and dictionary visibility fields through the reader snapshot' do
    popup = { component: 'dictionary-popup' }

    mutator.update_reader(
      dictionary_popup: popup,
      dictionary_visible: true,
      mode: :dictionary,
      popup_menu: nil
    )

    snapshot = reader_session_store.load
    expect(snapshot.dictionary_popup).to eq(popup)
    expect(snapshot.dictionary_visible).to be(true)
    expect(snapshot.mode).to eq(:dictionary)
  end

  it 'maps sidebar updates onto the reader snapshot' do
    mutator.update_sidebar(
      visible: true,
      active_tab: :annotations,
      annotations_selected: 3
    )

    snapshot = reader_session_store.load
    expect(snapshot.sidebar_visible).to be(true)
    expect(snapshot.sidebar_active_tab).to eq(:annotations)
    expect(snapshot.sidebar_annotations_selected).to eq(3)
  end

  it 'writes config updates through the app config store' do
    mutator.update_config(dictionary_target_lang: 'de')

    expect(app_config_store.load.dictionary_target_lang).to eq('de')
  end

  it 'clears the current selection and toggles view mode' do
    reader_session_store.save(reader_session_store.load.with(selection: { anchor: 1 }))

    mutator.clear_selection
    mutator.toggle_view_mode

    expect(reader_session_store.load.selection).to be_nil
    expect(app_config_store.load.view_mode).to eq(:split)
  end
end
