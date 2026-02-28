# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PageInfoCalculator do
  let(:ui_state_reader) do
    instance_double(
      'UiStateReader',
      terminal_width: 80,
      terminal_height: 24,
      terminal_size_changed?: true
    )
  end
  let(:layout_service) do
    instance_double('LayoutService', calculate_metrics: [80, 20], adjust_for_line_spacing: 10)
  end
  let(:page_calculator) { instance_double('PageCalculator', total_pages: 10) }
  let(:pagination_state_writer) { instance_double('PaginationStateWriter') }
  let(:ui_loading_writer) { instance_double('UiLoadingWriter') }
  let(:sidebar_state_reader) { instance_double('SidebarStateReader') }
  let(:pagination_orchestrator) do
    instance_double('PaginationOrchestrator', session: instance_double('Session', build_full_map: true))
  end

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
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader
    ).calculate
    expect(result).to eq(type: :single, current: 3, total: 10)
  end

  it 'calculates absolute split page info and builds page map when needed' do
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
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader
    ).calculate
    expect(result[:type]).to eq(:split)
    expect(result[:left][:current]).to eq(1)
    expect(result[:right][:current]).to eq(2)
  end

  it 'calls pagination orchestrator session with strict split-port keywords in absolute mode' do
    strict_orchestrator = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def session(doc:, page_calculator:, config_reader:, reader_state_reader:, pagination_state_writer:,
                  ui_loading_writer:, sidebar_state_reader:, dimensions: nil)
        @calls << {
          doc: doc,
          page_calculator: page_calculator,
          config_reader: config_reader,
          reader_state_reader: reader_state_reader,
          pagination_state_writer: pagination_state_writer,
          ui_loading_writer: ui_loading_writer,
          sidebar_state_reader: sidebar_state_reader,
          dimensions: dimensions
        }
        Struct.new(:build_full_map).new(true)
      end
    end.new

    split_config_reader = Object.new
    split_config_reader.define_singleton_method(:show_page_numbers) { true }
    split_config_reader.define_singleton_method(:view_mode) { :split }
    split_config_reader.define_singleton_method(:page_numbering_mode) { :absolute }
    split_config_reader.define_singleton_method(:line_spacing) { 0 }

    described_class.new(
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      ui_state_reader: ui_state_reader,
      pagination_orchestrator: strict_orchestrator,
      defer_page_map: false,
      config_reader: split_config_reader,
      reader_state_reader: reader_state_reader,
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader
    ).calculate

    expect(strict_orchestrator.calls).not_to be_empty
    call = strict_orchestrator.calls.first
    expect(call[:pagination_state_writer]).to eq(pagination_state_writer)
    expect(call[:ui_loading_writer]).to eq(ui_loading_writer)
    expect(call[:sidebar_state_reader]).to eq(sidebar_state_reader)
  end
end
