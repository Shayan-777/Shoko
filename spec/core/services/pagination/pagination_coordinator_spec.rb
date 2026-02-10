# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::Pagination::PaginationCoordinator do
  let(:doc) { instance_double('Doc') }
  let(:page_calculator) { instance_double('PageCalculator', total_pages: 10, apply_pending_precise_restore!: nil) }
  let(:layout_service) { instance_double('LayoutService') }
  let(:terminal_service) { instance_double('TerminalService', size: [24, 80]) }
  let(:pagination_cache) { instance_double('PaginationCache') }
  let(:frame_coordinator) { instance_double('FrameCoordinator') }
  let(:render_callback) { nil }
  let(:async_executor) { instance_double('AsyncExecutor', submit: nil) }
  let(:display_capabilities) { instance_double('DisplayCapabilities') }
  let(:instrumentation) { instance_double('Instrumentation') }
  let(:config_reader) { instance_double('ConfigReader', page_numbering_mode: :dynamic) }
  let(:reader_state_reader) { instance_double('ReaderStateReader', pending_progress: { chapter_index: 0, line_offset: 5 }) }
  let(:state_writer) { instance_double('StateWriter') }

  it 'applies pending progress when page map already exists' do
    coordinator = described_class.new(
      doc: doc,
      page_calculator: page_calculator,
      layout_service: layout_service,
      terminal_service: terminal_service,
      pagination_cache: pagination_cache,
      frame_coordinator: frame_coordinator,
      render_callback: render_callback,
      async_executor: async_executor,
      display_capabilities: display_capabilities,
      instrumentation: instrumentation,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer
    )

    expect(page_calculator).to receive(:apply_pending_precise_restore!)
      .with(reader_state_reader, state_writer: state_writer)

    coordinator.apply_pending_progress_if_ready
  end

  it 'skips applying pending progress when no pages are built' do
    allow(page_calculator).to receive(:total_pages).and_return(0)

    coordinator = described_class.new(
      doc: doc,
      page_calculator: page_calculator,
      layout_service: layout_service,
      terminal_service: terminal_service,
      pagination_cache: pagination_cache,
      frame_coordinator: frame_coordinator,
      render_callback: render_callback,
      async_executor: async_executor,
      display_capabilities: display_capabilities,
      instrumentation: instrumentation,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer
    )

    expect(page_calculator).not_to receive(:apply_pending_precise_restore!)

    coordinator.apply_pending_progress_if_ready
  end

  it 'routes sidebar layout sync through pagination session in dynamic mode' do
    coordinator = described_class.new(
      doc: doc,
      page_calculator: page_calculator,
      layout_service: layout_service,
      terminal_service: terminal_service,
      pagination_cache: pagination_cache,
      frame_coordinator: frame_coordinator,
      render_callback: render_callback,
      async_executor: async_executor,
      display_capabilities: display_capabilities,
      instrumentation: instrumentation,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer
    )

    session = instance_double('PaginationSession', sync_sidebar_layout: :switched)
    orchestrator = instance_double('PaginationOrchestrator', session: session)
    coordinator.instance_variable_set(:@orchestrator, orchestrator)

    expect(orchestrator).to receive(:session).with(
      doc: doc,
      page_calculator: page_calculator,
      dimensions: [80, 24],
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      state_writer: state_writer
    ).and_return(session)
    expect(session).to receive(:sync_sidebar_layout).with(sidebar_visible: true).and_return(:switched)

    result = coordinator.sync_sidebar_layout(sidebar_visible: true)
    expect(result).to eq(:switched)
  end
end
