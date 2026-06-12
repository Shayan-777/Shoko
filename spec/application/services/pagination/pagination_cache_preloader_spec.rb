# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PaginationCachePreloader do
  class PreloaderSnapshotStore
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
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

  class PreloaderMemoryPaginationCache
    def initialize
      @layouts = Hash.new { |hash, key| hash[key] = {} }
    end

    def layout_key(...)
      Shoko::Adapters::Storage::PaginationCache.layout_key(...)
    end

    def parse_layout_key(key)
      Shoko::Adapters::Storage::PaginationCache.parse_layout_key(key)
    end

    def save_for_document(doc, key, pages)
      @layouts[doc.object_id][key] = pages
    end

    def load_for_document(doc, key)
      @layouts[doc.object_id][key]
    end

    def exists_for_document?(doc, key)
      @layouts[doc.object_id].key?(key)
    end

    def layout_keys_for_document(doc)
      @layouts[doc.object_id].keys
    end
  end

  let(:terminal_size) { Struct.new(:width, :height).new(80, 24) }
  let(:display_capabilities) do
    instance_double('DisplayCapabilities').tap do |double|
      allow(double).to receive(:kitty_images_enabled?) { |config| config.kitty_images == true }
    end
  end
  let(:reader_runtime_context) do
    instance_double('ReaderRuntimeContext', terminal_size: terminal_size, display_capabilities: display_capabilities)
  end
  let(:pagination_cache) { PreloaderMemoryPaginationCache.new }
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:doc) { Object.new }
  let(:config_store) do
    PreloaderSnapshotStore.new(
      Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
        page_numbering_mode: :dynamic,
        view_mode: :single,
        line_spacing: :normal,
        kitty_images: false
      )
    )
  end
  let(:reader_session_store) do
    PreloaderSnapshotStore.new(
      Shoko::Application::Ports::Outbound::State::ReaderSnapshot.build(
        current_chapter: 1,
        current_page_index: 0,
        pending_progress: { chapter_index: 1, line_offset: 9 }
      )
    )
  end
  let(:reader_pagination_store) do
    PreloaderSnapshotStore.new(Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot.build)
  end
  let(:page_calculator) { instance_double('PageCalculator') }
  let(:preloader) do
    described_class.new(
      page_calculator: page_calculator,
      pagination_cache: pagination_cache,
      app_config_store: config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context,
      reader_state_reader: reader_session_store,
      reader_pagination_store: reader_pagination_store,
      logger: logger
    )
  end

  it 'returns :invalid when no document is provided' do
    result = preloader.preload(nil, width: 80, height: 24)

    expect(result.status).to eq(:invalid)
  end

  it 'returns :unavailable outside dynamic mode' do
    config_store.save(config_store.load.with(page_numbering_mode: :absolute))

    result = preloader.preload(doc, width: 80, height: 24)

    expect(result.status).to eq(:unavailable)
  end

  it 'returns :no_calculator when the page calculator is missing' do
    preloader_without_calculator = described_class.new(
      page_calculator: nil,
      pagination_cache: pagination_cache,
      app_config_store: config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context,
      reader_state_reader: reader_session_store,
      reader_pagination_store: reader_pagination_store,
      logger: logger
    )

    result = preloader_without_calculator.preload(doc, width: 80, height: 24)

    expect(result.status).to eq(:no_calculator)
  end

  it 'returns :miss with the requested layout key when no cache exists' do
    result = preloader.preload(doc, width: 80, height: 24)

    expect(result.status).to eq(:miss)
    expect(result.key).to eq(
      pagination_cache.layout_key(80, 24, :single, :normal, kitty_images: false, layout_variant: :base)
    )
  end

  it 'hydrates an exact cache hit and updates pagination and restore state' do
    key = pagination_cache.layout_key(80, 24, :single, :normal, kitty_images: false, layout_variant: :base)
    pages = [{ chapter_index: 1, page_in_chapter: 0, total_pages_in_chapter: 1, start_line: 0, end_line: 9 }]
    pagination_cache.save_for_document(doc, key, pages)
    allow(page_calculator).to receive(:hydrate_from_cache).and_return(
      total_pages: 1,
      last_width: 80,
      last_height: 24
    )
    allow(page_calculator).to receive(:apply_pending_precise_restore!).with(reader_session_store).and_return(
      current_page_index: 4,
      clear_pending_progress: true
    )

    result = preloader.preload(doc, width: 80, height: 24)

    expect(result.status).to eq(:hit)
    expect(result.key).to eq(key)
    expect(page_calculator).to have_received(:hydrate_from_cache).with(
      pages,
      doc: doc,
      width: 80,
      height: 24
    )
    expect(reader_pagination_store.load.total_pages).to eq(1)
    expect(reader_pagination_store.load.last_width).to eq(80)
    expect(reader_pagination_store.load.last_height).to eq(24)
    expect(reader_session_store.load.current_page_index).to eq(4)
    expect(reader_session_store.load.pending_progress).to be_nil
  end

  it 'uses a fallback cache layout only when view mode, spacing, kitty images, and variant all match' do
    config_store.save(config_store.load.with(kitty_images: true))
    correct_key = pagination_cache.layout_key(90, 28, :single, :normal, kitty_images: true, layout_variant: :base)
    wrong_image_key = pagination_cache.layout_key(90, 28, :single, :normal, kitty_images: false, layout_variant: :base)
    wrong_view_key = pagination_cache.layout_key(90, 28, :split, :normal, kitty_images: true, layout_variant: :base)
    pagination_cache.save_for_document(doc, wrong_image_key, [{ start_line: 0, end_line: 1 }])
    pagination_cache.save_for_document(doc, wrong_view_key, [{ start_line: 0, end_line: 1 }])
    pagination_cache.save_for_document(doc, correct_key, [{ start_line: 2, end_line: 8 }])
    allow(page_calculator).to receive(:hydrate_from_cache).and_return(
      total_pages: 1,
      last_width: 100,
      last_height: 30
    )
    allow(page_calculator).to receive(:apply_pending_precise_restore!).and_return(nil)

    result = preloader.preload(doc, width: 100, height: 30)

    expect(result.status).to eq(:hit)
    expect(result.key).to eq(correct_key)
    expect(page_calculator).to have_received(:hydrate_from_cache).with(
      [{ start_line: 2, end_line: 8 }],
      doc: doc,
      width: 100,
      height: 30
    )
  end

  it 'returns :error and logs when cache loading raises a typed failure' do
    allow(page_calculator).to receive(:apply_pending_precise_restore!).and_return(nil)
    allow(pagination_cache).to receive(:load_for_document).and_raise(Shoko::StorageError.new('load', nil, 'boom'))
    allow(logger).to receive(:debug)
    key = pagination_cache.layout_key(80, 24, :single, :normal, kitty_images: false, layout_variant: :base)
    pagination_cache.save_for_document(doc, key, [{ start_line: 0, end_line: 1 }])

    result = preloader.preload(doc, width: 80, height: 24)

    expect(result.status).to eq(:error)
    expect(logger).to have_received(:debug).with('PaginationCachePreloader: failed', error: include('boom'))
  end
end
