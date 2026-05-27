# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PageInfoCalculator do
  class PageInfoCalculatorTestConfigStore
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end
  end

  class PageInfoCalculatorTestReaderSessionStore
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def page_map
      @snapshot.page_map
    end

    def total_pages
      @snapshot.total_pages
    end

    def last_width
      @snapshot.last_width
    end

    def last_height
      @snapshot.last_height
    end
  end

  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 80, height: 24)
    )
  end
  let(:layout_service) do
    instance_double('LayoutService', calculate_metrics: [80, 20], adjust_for_line_spacing: 10)
  end
  let(:page_calculator) { instance_double('PageCalculator', total_pages: 10) }
  let(:pagination_runtime) do
    instance_double('PaginationRuntime', ensure_absolute_page_map: true)
  end

  it 'calculates dynamic single page info' do
    result = described_class.new(
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      reader_runtime_context: reader_runtime_context,
      pagination_runtime: pagination_runtime,
      defer_page_map: true,
      app_config_store: PageInfoCalculatorTestConfigStore.new(
        Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
          show_page_numbers: true,
          view_mode: :single,
          page_numbering_mode: :dynamic
        )
      ),
      reader_session_store: PageInfoCalculatorTestReaderSessionStore.new(
        Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
          current_page_index: 2,
          current_chapter: 0,
          total_pages: 10,
          page_map: [10]
        )
      )
    ).calculate

    expect(result).to eq(type: :single, current: 3, total: 10)
  end

  it 'calculates absolute split page info and builds page map when needed' do
    result = described_class.new(
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      reader_runtime_context: reader_runtime_context,
      pagination_runtime: pagination_runtime,
      defer_page_map: false,
      app_config_store: PageInfoCalculatorTestConfigStore.new(
        Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
          show_page_numbers: true,
          view_mode: :split,
          page_numbering_mode: :absolute
        )
      ),
      reader_session_store: PageInfoCalculatorTestReaderSessionStore.new(
        Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
          current_chapter: 0,
          left_page: 0,
          right_page: 10,
          single_page: 0,
          total_pages: 10,
          page_map: [10]
        )
      )
    ).calculate

    expect(result[:type]).to eq(:split)
    expect(result[:left][:current]).to eq(1)
    expect(result[:right][:current]).to eq(2)
  end

  it 'routes absolute pagination through the bound runtime' do
    strict_runtime = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def ensure_absolute_page_map(width:, height:)
        @calls << { width: width, height: height }
        true
      end
    end.new

    app_config_store = PageInfoCalculatorTestConfigStore.new(
      Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
        show_page_numbers: true,
        view_mode: :split,
        page_numbering_mode: :absolute
      )
    )
    reader_session_store = PageInfoCalculatorTestReaderSessionStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
        current_chapter: 0,
        left_page: 0,
        right_page: 10,
        total_pages: 10,
        page_map: []
      )
    )

    described_class.new(
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      reader_runtime_context: reader_runtime_context,
      pagination_runtime: strict_runtime,
      defer_page_map: false,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store
    ).calculate

    expect(strict_runtime.calls).to eq([{ width: 80, height: 24 }])
  end
end
