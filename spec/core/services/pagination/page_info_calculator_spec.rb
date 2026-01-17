# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::Pagination::PageInfoCalculator do
  let(:event_bus) { Shoko::Application::Infrastructure::EventBus.new }
  let(:state) { Shoko::Application::Infrastructure::ObserverStateStore.new(event_bus) }
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  let(:layout_service) do
    instance_double('LayoutService', calculate_metrics: [80, 20], adjust_for_line_spacing: 10)
  end
  let(:page_calculator) { instance_double('PageCalculator', total_pages: 10) }
  let(:pagination_orchestrator) do
    instance_double('PaginationOrchestrator', session: instance_double('Session', build_full_map: true))
  end

  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'calculates dynamic single page info' do
    state.update(
      %i[config show_page_numbers] => true,
      %i[config view_mode] => :single,
      %i[config page_numbering_mode] => :dynamic,
      %i[reader current_page_index] => 2
    )

    result = described_class.new(
      state: state,
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      terminal_service: terminal_service,
      pagination_orchestrator: pagination_orchestrator,
      defer_page_map: true
    ).calculate
    expect(result).to eq(type: :single, current: 3, total: 10)
  end

  it 'calculates absolute split page info and builds page map when needed' do
    state.update(
      %i[config show_page_numbers] => true,
      %i[config view_mode] => :split,
      %i[config page_numbering_mode] => :absolute,
      %i[reader page_map] => [10],
      %i[reader total_pages] => 10,
      %i[reader current_chapter] => 0,
      %i[reader left_page] => 0,
      %i[reader right_page] => 10
    )

    result = described_class.new(
      state: state,
      doc: double('Doc'),
      page_calculator: page_calculator,
      layout_service: layout_service,
      terminal_service: terminal_service,
      pagination_orchestrator: pagination_orchestrator,
      defer_page_map: false
    ).calculate
    expect(result[:type]).to eq(:split)
    expect(result[:left][:current]).to eq(1)
    expect(result[:right][:current]).to eq(2)
  end
end
