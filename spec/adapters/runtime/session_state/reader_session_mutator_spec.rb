# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator do
  class FailingReaderSessionStore
    include Shoko::Application::Ports::Outbound::ReaderSessionStore

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(_snapshot)
      raise Shoko::StateUpdateError, 'save failed'
    end
  end

  let(:terminal_capabilities) { Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new }
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }
  let(:config_dir) { @tmpdir }
  let(:config_storage) { SpecSupport::FakeConfigStorage.new(config_dir) }

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
  let(:state_store) do
    Shoko::Application::State::StateStore.new(
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities,
      schema_registry: schema_registry
    )
  end
  let(:reader_session_store) do
    Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter.new(state_store)
  end
  let(:reader_view_state_store) do
    Shoko::Adapters::Runtime::SessionState::ReaderViewStateStoreAdapter.new(state_store)
  end
  let(:reader_pagination_store) do
    Shoko::Adapters::Runtime::SessionState::ReaderPaginationStoreAdapter.new(state_store)
  end
  let(:reader_state_reader) do
    Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter.new(
      state: state_store,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      component_registry: component_registry
    )
  end
  let(:app_config_store) do
    Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter.new(state_store)
  end
  let(:component_registry) { Shoko::Adapters::Ui::State::ReaderComponentRegistry.new }

  subject(:mutator) do
    described_class.new(
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      app_config_store: app_config_store,
      component_registry: component_registry
    )
  end

  it 'writes live UI objects through the adapter-owned registry and keeps pure flags in the snapshot' do
    popup = { component: 'dictionary-popup' }

    mutator.update_reader(
      dictionary_popup: popup,
      dictionary_visible: true,
      mode: :dictionary,
      popup_menu: nil
    )

    snapshot = reader_state_reader.load
    expect(snapshot.to_h).not_to have_key(:dictionary_popup)
    expect(reader_view_state_store.load.dictionary_visible).to be(true)
    expect(reader_session_store.load.mode).to eq(:dictionary)
    expect(component_registry.read(:dictionary_popup)).to eq(popup)
  end

  it 'rolls back live UI registry writes when snapshot persistence fails' do
    popup = { component: 'dictionary-popup' }
    failing_store = FailingReaderSessionStore.new(reader_session_store.load)
    mutator = described_class.new(
      reader_session_store: failing_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      app_config_store: app_config_store,
      component_registry: component_registry
    )

    expect do
      mutator.update_reader(dictionary_popup: popup, mode: :dictionary)
    end.to raise_error(Shoko::StateUpdateError, /save failed/)

    expect(component_registry.read(:dictionary_popup)).to be_nil
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
