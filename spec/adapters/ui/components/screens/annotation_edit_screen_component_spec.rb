# frozen_string_literal: true

require 'spec_helper'
require 'shoko/test_support/terminal_double'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::AnnotationEditScreenComponent do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:terminal_capabilities) { Shoko::Core::Services::DefaultTerminalCapabilities.new }
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

  let(:dependencies) do
    state = state_store
    Class.new do
      define_method(:initialize) { |s| @state = s }
      define_method(:menu_state_reader) { Shoko::Adapters::Runtime::SessionState::MenuStateReaderAdapter.new(@state) }
      define_method(:menu_state_writer) { Shoko::Adapters::Runtime::SessionState::MenuStateWriterAdapter.new(@state) }
      define_method(:annotation_service) { nil }
    end.new(state)
  end

  it 'renders the annotation editor without raising' do
    state_store.dispatch(
      Shoko::Adapters::Runtime::SessionState::Actions::UpdateMenuAction.new(
        selected_annotation: { 'id' => '1', 'text' => 'Hello', 'note' => 'Note' },
        selected_annotation_book: '/tmp/book.epub',
        annotation_edit_text: 'Note',
        annotation_edit_cursor: 4
      )
    )

    terminal.reset!
    surface = Shoko::Adapters::Ui::Components::Surface.new(terminal)
    bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 80, height: 24)

    component = described_class.new(dependencies)
    component.render(surface, bounds)

    output = terminal.writes.map { |write| write[:text] }.join
    expect(output).to include('Edit Annotation')
  end
end
