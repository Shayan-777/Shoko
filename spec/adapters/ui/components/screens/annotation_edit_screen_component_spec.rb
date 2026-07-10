# frozen_string_literal: true

require 'spec_helper'
require 'shoko/test_support/terminal_double'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::AnnotationEditScreenComponent do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
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

  let(:dependencies) do
    state = state_store
    Class.new do
      define_method(:initialize) { |s| @state = s }
      define_method(:menu_state_reader) do
        Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(@state)
      end
      define_method(:menu_session_mutator) do
        Shoko::Adapters::Runtime::SessionState::MenuSessionMutator.new(
          menu_session_store: Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(@state)
        )
      end
      define_method(:annotation_service) { nil }
    end.new(state)
  end

  it 'renders the annotation editor without raising' do
    state_store.update(
      [:menu, :selected_annotation] => { 'id' => '1', 'text' => 'Hello', 'note' => 'Note' },
      [:menu, :selected_annotation_book] => '/tmp/book.epub',
      [:menu, :annotation_edit_text] => 'Note',
      [:menu, :annotation_edit_cursor] => 4
    )

    terminal.reset!
    surface = Shoko::Adapters::Ui::Components::Surface.new(terminal)
    bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 80, height: 24)

    component = described_class.new(dependencies)
    component.render(surface, bounds)

    output = terminal.writes.map { |write| write[:text] }.join
    expect(output).to include('Edit Annotation')
    expect(output).to include('SELECTED TEXT')
    expect(output).to include('Hello')
    expect(output).to include('line 1, col 5')
    expect(output).to include(Shoko::Adapters::Ui::Components::StatusBar::Palette::NOTES_FIELD_BG)
  end
end
