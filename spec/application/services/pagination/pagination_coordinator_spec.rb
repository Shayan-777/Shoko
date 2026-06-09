# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PaginationCoordinator do
  class PaginationCoordinatorTestRenderRequester
    include Shoko::Application::Ports::Outbound::ReaderRenderRequester

    def request_render(reason:)
      reason
    end
  end

  class PaginationCoordinatorTestConfigStore
    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  class PaginationCoordinatorTestReaderSessionStore
    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end

    def total_pages
      @snapshot.total_pages
    end
  end

  class PaginationCoordinatorTestReaderRuntimeContext
    include Shoko::Application::Ports::Outbound::ReaderRuntimeContext

    def initialize(terminal_size:, display_capabilities:)
      @terminal_size = terminal_size
      @display_capabilities = display_capabilities
    end

    def terminal_size
      @terminal_size
    end

    def display_capabilities
      @display_capabilities
    end
  end

  let(:doc) { instance_double('Doc', cached?: false) }
  let(:page_calculator) do
    instance_double('PageCalculator', total_pages: 10, apply_pending_precise_restore!: nil, reset_session!: nil)
  end
  let(:layout_service) { instance_double('LayoutService') }
  let(:pagination_cache) { instance_double('PaginationCache') }
  let(:reader_render_requester) { PaginationCoordinatorTestRenderRequester.new }
  let(:async_executor) { instance_double('AsyncExecutor', submit: nil) }
  let(:instrumentation) { instance_double('Instrumentation') }
  let(:display_capabilities) { instance_double('DisplayCapabilities', kitty_images_enabled?: false) }
  let(:reader_runtime_context) do
    PaginationCoordinatorTestReaderRuntimeContext.new(
      terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 80, height: 24),
      display_capabilities: display_capabilities
    )
  end
  let(:app_config_store) do
    PaginationCoordinatorTestConfigStore.new(
      Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(page_numbering_mode: :dynamic)
    )
  end
  let(:reader_session_store) do
    PaginationCoordinatorTestReaderSessionStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
        pending_progress: { chapter_index: 0, line_offset: 5 }
      )
    )
  end
  let(:logger) { instance_double('Logger', debug: nil) }

  def build_coordinator(notification_writer: nil, logger: nil)
    described_class.new(
      doc: doc,
      page_calculator: page_calculator,
      layout_service: layout_service,
      pagination_cache: pagination_cache,
      reader_render_requester: reader_render_requester,
      async_executor: async_executor,
      instrumentation: instrumentation,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context,
      notification_writer: notification_writer,
      logger: logger
    )
  end

  it 'applies pending progress when page map already exists' do
    coordinator = build_coordinator

    expect(page_calculator).to receive(:apply_pending_precise_restore!)
      .with(reader_session_store.load)
      .and_return(current_page_index: 2, clear_pending_progress: true)

    coordinator.apply_pending_progress_if_ready

    snapshot = reader_session_store.load
    expect(snapshot.current_page_index).to eq(2)
    expect(snapshot.pending_progress).to be_nil
  end

  it 'skips applying pending progress when no pages are built' do
    allow(page_calculator).to receive(:total_pages).and_return(0)
    coordinator = build_coordinator

    expect(page_calculator).not_to receive(:apply_pending_precise_restore!)

    coordinator.apply_pending_progress_if_ready
  end

  it 'routes sidebar layout sync through the bound pagination runtime in dynamic mode' do
    coordinator = build_coordinator

    runtime = instance_double('PaginationRuntime')
    coordinator.instance_variable_set(:@pagination_runtime, runtime)

    expect(runtime).to receive(:sync_sidebar_layout)
      .with(dimensions: [80, 24], sidebar_visible: true)
      .and_return(:switched)

    result = coordinator.sync_sidebar_layout(sidebar_visible: true)
    expect(result).to eq(:switched)
  end

  it 'rebuilds pagination through the bound runtime and requests a render' do
    coordinator = build_coordinator
    runtime = instance_double('PaginationRuntime')
    coordinator.instance_variable_set(:@pagination_runtime, runtime)

    expect(runtime).to receive(:rebuild_dynamic).and_return(:handled)
    expect(reader_render_requester).to receive(:request_render).with(reason: 'pagination.rebuild_dynamic')

    expect(coordinator.rebuild_dynamic).to eq(:handled)
  end

  it 'keeps pagination rebuild successful when render requester raises typed failure' do
    coordinator = build_coordinator(logger: logger)
    runtime = instance_double('PaginationRuntime')
    coordinator.instance_variable_set(:@pagination_runtime, runtime)

    expect(runtime).to receive(:rebuild_dynamic).and_return(:handled)
    allow(reader_render_requester).to receive(:request_render).and_raise(
      Shoko::Application::Ports::Outbound::ReaderRenderRequester::RenderRequestError,
      'draw failure'
    )
    expect(logger).to receive(:debug).with(/pagination\.request_render failed/)

    expect(coordinator.rebuild_dynamic).to eq(:handled)
  end

  describe 'background repagination feedback' do
    it 'is not recalculating before any work starts' do
      expect(build_coordinator.recalculating?).to be(false)
    end

    it 'flags recalculating synchronously and coalesces concurrent resizes into one job' do
      coordinator = build_coordinator
      coordinator.instance_variable_set(:@pagination_runtime, instance_double('PaginationRuntime'))
      allow(async_executor).to receive(:submit) # leave the job in flight

      expect(coordinator.refresh_after_resize(width: 100, height: 40)).to be(true)
      expect(coordinator.recalculating?).to be(true)
      # a resize arriving while one is in flight coalesces — no second job
      expect(coordinator.refresh_after_resize(width: 120, height: 50)).to be(false)
      expect(async_executor).to have_received(:submit).once
    end

    it 'clears the recalculating flag after the background resize completes' do
      coordinator = build_coordinator
      runtime = instance_double('PaginationRuntime', refresh_after_resize: nil)
      coordinator.instance_variable_set(:@pagination_runtime, runtime)
      captured_job = nil
      allow(async_executor).to receive(:submit) { |&block| captured_job = block }

      coordinator.refresh_after_resize(width: 100, height: 40)
      expect(coordinator.recalculating?).to be(true)

      captured_job.call

      expect(coordinator.recalculating?).to be(false)
      expect(runtime).to have_received(:refresh_after_resize)
        .with(width: 100, height: 40, progress: kind_of(Method))
    end
  end

  it 'invalidates pagination cache via session and publishes success notification' do
    notification_writer = instance_double('NotificationWriter', show_message: nil)
    coordinator = build_coordinator(notification_writer: notification_writer)

    runtime = instance_double('PaginationRuntime')
    coordinator.instance_variable_set(:@pagination_runtime, runtime)

    expect(runtime).to receive(:invalidate_cache).with(dimensions: [80, 24]).and_return(:deleted)
    expect(notification_writer).to receive(:show_message).with('Pagination cache cleared')

    expect(coordinator.invalidate_cache).to eq(:handled)
  end
end
