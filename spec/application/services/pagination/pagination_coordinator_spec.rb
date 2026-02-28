# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PaginationCoordinator do
  class TestRenderRequester
    include Shoko::Core::Ports::Outbound::ReaderRenderRequester

    def request_render(reason:)
      reason
    end
  end

  let(:doc) { instance_double('Doc', cached?: false) }
  let(:page_calculator) { instance_double('PageCalculator', total_pages: 10, apply_pending_precise_restore!: nil, reset_session!: nil) }
  let(:layout_service) { instance_double('LayoutService') }
  let(:ui_state_reader) { instance_double('UiStateReader', terminal_width: 80, terminal_height: 24) }
  let(:pagination_cache) { instance_double('PaginationCache') }
  let(:reader_render_requester) { TestRenderRequester.new }
  let(:async_executor) { instance_double('AsyncExecutor', submit: nil) }
  let(:display_capabilities) { instance_double('DisplayCapabilities') }
  let(:instrumentation) { instance_double('Instrumentation') }
  let(:config_reader) { instance_double('ConfigReader', page_numbering_mode: :dynamic) }
  let(:reader_state_reader) { instance_double('ReaderStateReader', pending_progress: { chapter_index: 0, line_offset: 5 }) }
  let(:sidebar_state_reader) { instance_double('SidebarStateReader', sidebar_visible?: false) }
  let(:pagination_state_writer) { instance_double('PaginationStateWriter', update_page: nil, update_selections: nil) }
  let(:ui_loading_writer) { instance_double('UiLoadingWriter') }
  let(:logger) { instance_double('Logger', debug: nil) }

  def build_coordinator(notification_writer: nil, logger: nil)
    described_class.new(
      doc: doc,
      page_calculator: page_calculator,
      layout_service: layout_service,
      ui_state_reader: ui_state_reader,
      pagination_cache: pagination_cache,
      reader_render_requester: reader_render_requester,
      async_executor: async_executor,
      display_capabilities: display_capabilities,
      instrumentation: instrumentation,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader,
      notification_writer: notification_writer,
      logger: logger
    )
  end

  it 'applies pending progress when page map already exists' do
    coordinator = build_coordinator

    expect(page_calculator).to receive(:apply_pending_precise_restore!)
      .with(reader_state_reader)
      .and_return(current_page_index: 2, clear_pending_progress: true)
    expect(pagination_state_writer).to receive(:update_page).with(current_page_index: 2)
    expect(pagination_state_writer).to receive(:update_selections).with(pending_progress: nil)

    coordinator.apply_pending_progress_if_ready
  end

  it 'skips applying pending progress when no pages are built' do
    allow(page_calculator).to receive(:total_pages).and_return(0)
    coordinator = build_coordinator

    expect(page_calculator).not_to receive(:apply_pending_precise_restore!)

    coordinator.apply_pending_progress_if_ready
  end

  it 'routes sidebar layout sync through pagination session in dynamic mode' do
    coordinator = build_coordinator

    session = instance_double('PaginationSession', sync_sidebar_layout: :switched)
    orchestrator = instance_double('PaginationOrchestrator', session: session)
    coordinator.instance_variable_set(:@orchestrator, orchestrator)

    expect(orchestrator).to receive(:session).with(
      doc: doc,
      page_calculator: page_calculator,
      dimensions: [80, 24],
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader
    ).and_return(session)
    expect(session).to receive(:sync_sidebar_layout).with(sidebar_visible: true).and_return(:switched)

    result = coordinator.sync_sidebar_layout(sidebar_visible: true)
    expect(result).to eq(:switched)
  end

  it 'rebuilds pagination through session and requests a render' do
    coordinator = build_coordinator
    session = instance_double('PaginationSession', rebuild_dynamic: :handled)
    orchestrator = instance_double('PaginationOrchestrator')
    coordinator.instance_variable_set(:@orchestrator, orchestrator)

    expect(orchestrator).to receive(:session).with(
      doc: doc,
      page_calculator: page_calculator,
      dimensions: nil,
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader
    ).and_return(session)
    expect(session).to receive(:rebuild_dynamic).and_return(:handled)
    expect(reader_render_requester).to receive(:request_render).with(reason: 'pagination.rebuild_dynamic')

    expect(coordinator.rebuild_dynamic).to eq(:handled)
  end

  it 'keeps pagination rebuild successful when render requester raises typed failure' do
    coordinator = build_coordinator(logger: logger)
    session = instance_double('PaginationSession', rebuild_dynamic: :handled)
    orchestrator = instance_double('PaginationOrchestrator')
    coordinator.instance_variable_set(:@orchestrator, orchestrator)

    expect(orchestrator).to receive(:session).and_return(session)
    expect(session).to receive(:rebuild_dynamic).and_return(:handled)
    allow(reader_render_requester).to receive(:request_render).and_raise(
      Shoko::Core::Ports::Outbound::ReaderRenderRequester::RenderRequestError,
      'draw failure'
    )
    expect(logger).to receive(:debug).with(/pagination\.request_render failed/)

    expect(coordinator.rebuild_dynamic).to eq(:handled)
  end

  it 'invalidates pagination cache via session and publishes success notification' do
    notification_writer = instance_double('NotificationWriter', show_message: nil)
    coordinator = build_coordinator(notification_writer: notification_writer)

    session = instance_double('PaginationSession', invalidate_cache: :deleted)
    orchestrator = instance_double('PaginationOrchestrator')
    coordinator.instance_variable_set(:@orchestrator, orchestrator)

    expect(orchestrator).to receive(:session).with(
      doc: doc,
      page_calculator: page_calculator,
      dimensions: [80, 24],
      config_reader: config_reader,
      reader_state_reader: reader_state_reader,
      pagination_state_writer: pagination_state_writer,
      ui_loading_writer: ui_loading_writer,
      sidebar_state_reader: sidebar_state_reader
    ).and_return(session)
    expect(session).to receive(:invalidate_cache).and_return(:deleted)
    expect(notification_writer).to receive(:show_message).with('Pagination cache cleared')

    expect(coordinator.invalidate_cache).to eq(:handled)
  end
end
