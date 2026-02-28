# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PageInfoCalculator do
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
  let(:event_bus) { Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger) }
  let(:state) do
    Shoko::Adapters::Runtime::SessionState::ObserverStateStore.new(
      event_bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities
    )
  end
  let(:ui_state_reader) { instance_double('UiStateReader', terminal_width: 80, terminal_height: 24, terminal_size_changed?: true) }
  let(:layout_service) do
    instance_double('LayoutService', calculate_metrics: [80, 20], adjust_for_line_spacing: 10)
  end
  let(:page_calculator) { instance_double('PageCalculator', total_pages: 10) }
  let(:pagination_orchestrator) do
    instance_double('PaginationOrchestrator', session: instance_double('Session', build_full_map: true))
  end

  # Port mocks
  let(:config_reader) do
    reader = Object.new
    reader.define_singleton_method(:show_page_numbers) { true }
    reader.define_singleton_method(:view_mode) { :single }
    reader.define_singleton_method(:page_numbering_mode) { :dynamic }
    reader.define_singleton_method(:line_spacing) { 0 }
    reader
  end

  let(:reader_state_reader) do
    reader = Object.new
    reader.define_singleton_method(:current_page_index) { 2 }
    reader.define_singleton_method(:current_chapter) { 0 }
    reader.define_singleton_method(:left_page) { 0 }
    reader.define_singleton_method(:right_page) { 10 }
    reader.define_singleton_method(:single_page) { 0 }
    reader.define_singleton_method(:total_pages) { 10 }
    reader.define_singleton_method(:page_map) { [10] }
    reader
  end

  let(:state_writer) do
    writer = Object.new
    writer.define_singleton_method(:update_pagination_state) { |_attrs| nil }
    writer
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'calculates dynamic single page info' do
    result = described_class.new(
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      ui_state_reader: ui_state_reader,
      pagination_orchestrator: pagination_orchestrator,
      defer_page_map: true,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer
    ).calculate
    expect(result).to eq(type: :single, current: 3, total: 10)
  end

  it 'calculates absolute split page info and builds page map when needed' do
    # Override config_reader for absolute mode with split view
    split_config_reader = Object.new
    split_config_reader.define_singleton_method(:show_page_numbers) { true }
    split_config_reader.define_singleton_method(:view_mode) { :split }
    split_config_reader.define_singleton_method(:page_numbering_mode) { :absolute }
    split_config_reader.define_singleton_method(:line_spacing) { 0 }

    result = described_class.new(
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      ui_state_reader: ui_state_reader,
      pagination_orchestrator: pagination_orchestrator,
      defer_page_map: false,
      config_reader: split_config_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer
    ).calculate
    expect(result[:type]).to eq(:split)
    expect(result[:left][:current]).to eq(1)
    expect(result[:right][:current]).to eq(2)
  end
end
