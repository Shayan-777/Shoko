# frozen_string_literal: true

require 'spec_helper'
require 'shoko/test_support/terminal_double'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::AnnotationEditScreenComponent do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
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

  let(:dependencies) do
    state = state_store
    Class.new do
      define_method(:initialize) { |s| @state = s }
      define_method(:menu_state_reader) do
        Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(@state)
      end
      define_method(:menu_session_mutator) do
        Shoko::Adapters::Runtime::SessionState::MenuSessionMutator.new(
          menu_session_store: Shoko::Adapters::Runtime::SessionState::MenuSessionStoreAdapter.new(@state),
          menu_transient_store: Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter.new(@state)
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

    component = described_class.new(
      menu_state_reader: dependencies.menu_state_reader,
      menu_session_mutator: dependencies.menu_session_mutator,
      annotation_service: dependencies.annotation_service
    )
    component.render(surface, bounds)

    output = terminal.writes.map { |write| write[:text] }.join
    expect(output).to include('Edit Annotation')
    expect(output).to include('SELECTED TEXT')
    expect(output).to include('Hello')
    expect(output).to include('line 1, col 5')
    expect(output).to include(Shoko::Adapters::Ui::Components::StatusBar::Palette::NOTES_FIELD_BG)
  end


  it 'owns the complete edit-state mutation behavior after the one-use helper is removed' do
    state_store.update(
      [:menu, :annotation_edit_text] => 'Note',
      [:menu, :annotation_edit_cursor] => 4
    )
    reader = dependencies.menu_state_reader
    component = described_class.new(
      menu_state_reader: reader,
      menu_session_mutator: dependencies.menu_session_mutator
    )

    component.handle_character('!')
    component.handle_move_left
    component.handle_backspace
    component.handle_enter

    expect(reader.annotation_edit_text).to eq("Not\n!")
    expect(reader.annotation_edit_cursor).to eq(4)
  end


  it 'persists the selected annotation, refreshes the list, and returns to list mode' do
    state_store.update(
      [:menu, :selected_annotation] => { 'id' => 'ann-1', 'text' => 'Quote' },
      [:menu, :selected_annotation_book] => '/tmp/book.epub',
      [:menu, :annotation_edit_text] => 'Revised note'
    )
    annotations = [{ id: 'ann-1', text: 'Quote', note: 'Revised note' }]
    service = instance_double(Shoko::Core::Services::AnnotationService, list_all: annotations)
    reader = dependencies.menu_state_reader
    component = described_class.new(
      menu_state_reader: reader,
      menu_session_mutator: dependencies.menu_session_mutator,
      annotation_service: service
    )

    expect(service).to receive(:update).with('/tmp/book.epub', 'ann-1', 'Revised note')
    component.save_annotation

    expect(state_store.peek_at(:menu, :annotations_all)).to eq(annotations)
    expect(reader.mode).to eq(:annotations)
  end
end
