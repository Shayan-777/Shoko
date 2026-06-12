# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PaginationOrchestrator do
  class OrchestratorSnapshotStore
    attr_reader :saved_snapshots

    def initialize(snapshot)
      @snapshot = snapshot
      @saved_snapshots = []
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @saved_snapshots << snapshot
      @snapshot = snapshot
    end

    def respond_to_missing?(method_name, include_private = false)
      @snapshot.respond_to?(method_name, include_private) || super
    end

    def method_missing(method_name, ...)
      return @snapshot.public_send(method_name, ...) if @snapshot.respond_to?(method_name)

      super
    end
  end

  class OrchestratorMemoryPaginationCache
    attr_accessor :delete_error

    def initialize
      @layouts = Hash.new { |hash, key| hash[key] = {} }
    end

    def layout_key(...)
      Shoko::Adapters::Storage::PaginationCache.layout_key(...)
    end

    def parse_layout_key(key)
      Shoko::Adapters::Storage::PaginationCache.parse_layout_key(key)
    end

    def load_for_document(doc, key)
      @layouts[doc.object_id][key]
    end

    def save_for_document(doc, key, pages)
      @layouts[doc.object_id][key] = pages
    end

    def delete_for_document(doc, key)
      raise @delete_error if @delete_error

      @layouts[doc.object_id].delete(key)
    end

    def exists_for_document?(doc, key)
      @layouts[doc.object_id].key?(key)
    end

    def layout_keys_for_document(doc)
      @layouts[doc.object_id].keys
    end
  end

  class OrchestratorTestReaderRuntimeContext
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

  let(:terminal_size) { Struct.new(:width, :height).new(88, 33) }
  let(:display_capabilities) { instance_double('DisplayCapabilities', kitty_images_enabled?: false) }
  let(:reader_runtime_context) do
    OrchestratorTestReaderRuntimeContext.new(
      terminal_size: terminal_size,
      display_capabilities: display_capabilities
    )
  end
  let(:instrumentation) { instance_double('Instrumentation') }
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:pagination_cache) { OrchestratorMemoryPaginationCache.new }
  let(:orchestrator) do
    described_class.new(
      reader_runtime_context: reader_runtime_context,
      instrumentation: instrumentation,
      pagination_cache: pagination_cache,
      logger: logger
    )
  end
  let(:doc) { Object.new }

  before do
    allow(instrumentation).to receive(:measure) { |_metric, &block| block&.call }
    allow(instrumentation).to receive(:annotate)
  end

  def build_runtime(config_attrs: {}, session_attrs: {}, view_attrs: {}, pagination_attrs: {}, page_calculator:)
    config_store = OrchestratorSnapshotStore.new(
      Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
        {
          page_numbering_mode: :dynamic,
          view_mode: :single,
          line_spacing: :normal,
        }.merge(config_attrs)
      )
    )
    reader_session_store = OrchestratorSnapshotStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
        {
          current_chapter: 2,
          current_page_index: 1,
          pending_progress: { chapter_index: 2, line_offset: 14 },
        }.merge(session_attrs)
      )
    )
    reader_view_state_store = OrchestratorSnapshotStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot.build({ sidebar_visible: false }.merge(view_attrs))
    )
    reader_pagination_store = OrchestratorSnapshotStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot.build(pagination_attrs)
    )

    runtime = orchestrator.bind(
      doc: doc,
      page_calculator: page_calculator,
      app_config_store: config_store,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store
    )

    {
      runtime: runtime,
      config_store: config_store,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
    }
  end

  it 'returns a runtime handle with the existing bind contract' do
    page_calculator = instance_double('PageCalculator')
    runtime = build_runtime(page_calculator: page_calculator).fetch(:runtime)

    expect(runtime).to respond_to(
      :initial_build,
      :build_full_map,
      :refresh_after_resize,
      :rebuild_after_config_change,
      :rebuild_dynamic,
      :sync_sidebar_layout,
      :invalidate_cache,
      :ensure_absolute_page_map
    )
  end

  it 'resolves terminal dimensions when a runtime call omits them' do
    page_calculator = instance_double('PageCalculator')
    allow(page_calculator).to receive(:build_absolute_map!).and_return(
      page_map: [2, 3],
      total_pages: 5,
      last_width: 88,
      last_height: 33
    )

    state = build_runtime(
      config_attrs: { page_numbering_mode: :absolute },
      page_calculator: page_calculator
    )
    result = state.fetch(:runtime).initial_build

    expect(page_calculator).to have_received(:build_absolute_map!).with(
      88,
      33,
      doc,
      config_reader: state.fetch(:config_store).load
    )
    expect(result).to eq(
      page_map_cache: {
        key: pagination_cache.layout_key(88, 33, :single, :normal, kitty_images: false, layout_variant: :base),
        map: [2, 3],
        total: 5,
      }
    )
  end

  it 'toggles loading state, reports progress, persists pagination, and applies pending restore on dynamic initial build' do
    page_calculator = instance_double('PageCalculator')
    allow(page_calculator).to receive(:build_dynamic_map!) do |_width, _height, _doc, config_reader:, sidebar_visible:, &progress|
      expect(config_reader.page_numbering_mode).to eq(:dynamic)
      expect(sidebar_visible).to be(false)
      progress&.call(1, 4)
      {
        pages: [{ chapter_index: 2, start_line: 14, end_line: 20 }],
        total_pages: 4,
        last_width: 80,
        last_height: 24,
      }
    end
    allow(page_calculator).to receive(:apply_pending_precise_restore!).and_return(
      current_page_index: 3,
      clear_pending_progress: true
    )

    state = build_runtime(page_calculator: page_calculator)
    result = state.fetch(:runtime).initial_build(dimensions: [80, 24])

    expect(result).to eq(page_map_cache: nil)
    expect(state.fetch(:reader_view_state_store).saved_snapshots.map(&:loading_active?)).to include(true, false)
    expect(state.fetch(:reader_view_state_store).saved_snapshots.map(&:loading_progress)).to include(0.25)
    expect(state.fetch(:reader_pagination_store).load.total_pages).to eq(4)
    expect(state.fetch(:reader_pagination_store).load.last_width).to eq(80)
    expect(state.fetch(:reader_pagination_store).load.last_height).to eq(24)
    expect(state.fetch(:reader_session_store).load.current_page_index).to eq(3)
    expect(state.fetch(:reader_session_store).load.pending_progress).to be_nil
  end

  it 'returns an absolute cache entry using the shared layout key semantics' do
    page_calculator = instance_double('PageCalculator')
    allow(page_calculator).to receive(:build_absolute_map!).and_return(
      page_map: [1, 4, 2],
      total_pages: 7,
      last_width: 90,
      last_height: 30
    )

    state = build_runtime(
      config_attrs: { page_numbering_mode: :absolute },
      page_calculator: page_calculator
    )
    result = state.fetch(:runtime).initial_build(dimensions: [90, 30])

    expect(result.fetch(:page_map_cache)).to eq(
      key: pagination_cache.layout_key(90, 30, :single, :normal, kitty_images: false, layout_variant: :base),
      map: [1, 4, 2],
      total: 7
    )
  end

  it 'keeps cache invalidation status semantics unchanged' do
    page_calculator = instance_double('PageCalculator')
    state = build_runtime(page_calculator: page_calculator)
    runtime = state.fetch(:runtime)
    key = pagination_cache.layout_key(80, 24, :single, :normal, kitty_images: false, layout_variant: :base)
    pagination_cache.save_for_document(doc, key, [{ chapter_index: 0, start_line: 0, end_line: 1 }])

    expect(runtime.invalidate_cache(dimensions: [80, 24])).to eq(:deleted)
    expect(runtime.invalidate_cache(dimensions: [81, 24])).to eq(:missing)

    pagination_cache.save_for_document(doc, key, [{ chapter_index: 0, start_line: 0, end_line: 1 }])
    pagination_cache.delete_error = Shoko::StorageError.new('delete', nil, 'boom')

    expect(runtime.invalidate_cache(dimensions: [80, 24])).to eq(:error)
  end
end
