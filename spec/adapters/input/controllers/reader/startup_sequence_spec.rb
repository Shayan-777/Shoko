# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::StartupSequence do
  let(:terminal_session) { instance_double('TerminalSession', size: [40, 120]) }
  let(:async_executor) { instance_double('AsyncExecutor') }
  let(:state_controller) do
    instance_double('StateController', load_progress: nil, load_bookmarks: nil, refresh_annotations: nil)
  end
  let(:pagination_cache_preloader) { instance_double('PaginationCachePreloader', preload: nil) }
  let(:image_cache_warmup) { instance_double('ImageCacheWarmup', warm_document: nil) }
  let(:kitty_image_renderer) { instance_double('KittyImageRenderer', reset_virtual_placements!: nil) }
  let(:doc) { instance_double('Document', cached?: false) }
  let(:config_reader) { instance_double('ConfigReader', kitty_images: true) }
  let(:pagination_coordinator) { instance_double('PaginationCoordinator', apply_pending_progress_if_ready: nil) }
  let(:controller) do
    instance_double(
      'Controller',
      doc: doc,
      config_reader: config_reader,
      pagination_coordinator: pagination_coordinator,
      clear_defer_page_map!: nil,
      arm_deferred_page_map!: nil,
      perform_initial_calculations_if_needed: nil,
      pending_initial_calculation?: false,
      schedule_background_page_map_build: nil,
      defer_page_map?: false,
      state_controller: state_controller
    )
  end

  subject(:sequence) do
    described_class.new(
      terminal_session: terminal_session,
      async_executor: async_executor,
      state_controller: state_controller,
      pagination_cache_preloader: pagination_cache_preloader,
      image_cache_warmup: image_cache_warmup,
      kitty_image_renderer: kitty_image_renderer
    )
  end

  it 'queues image cache warming as a background startup task when kitty images are enabled' do
    expect(async_executor).to receive(:submit).twice do |&job|
      job.call
    end
    expect(state_controller).to receive(:load_progress).ordered
    expect(pagination_coordinator).to receive(:apply_pending_progress_if_ready).ordered
    expect(kitty_image_renderer).to receive(:reset_virtual_placements!).ordered
    expect(state_controller).to receive(:load_bookmarks).ordered
    expect(state_controller).to receive(:refresh_annotations).ordered
    expect(image_cache_warmup).to receive(:warm_document).with(doc).ordered

    sequence.start(controller)
  end

  it 'contains background submits refused by a stopping worker' do
    allow(async_executor).to receive(:submit)
      .and_raise(Shoko::Adapters::Storage::BackgroundWorker::WorkerStoppedError, 'worker is shutting down')

    expect { sequence.start(controller) }.not_to raise_error
  end

  it 'skips image cache warming when kitty images are disabled' do
    allow(config_reader).to receive(:kitty_images).and_return(false)

    expect(async_executor).to receive(:submit).once do |&job|
      job.call
    end
    expect(kitty_image_renderer).not_to receive(:reset_virtual_placements!)
    expect(image_cache_warmup).not_to receive(:warm_document)

    sequence.start(controller)
  end

  describe 'cached pagination preload outcomes' do
    let(:doc) { instance_double('Document', cached?: true) }
    let(:preload_result) { Struct.new(:status, :key) }

    before do
      allow(config_reader).to receive(:kitty_images).and_return(false)
      allow(async_executor).to receive(:submit)
    end

    it 'clears the deferred build on an exact-size hit' do
      allow(pagination_cache_preloader).to receive(:preload)
        .and_return(preload_result.new(:hit, 'k'))

      sequence.start(controller)

      expect(controller).to have_received(:clear_defer_page_map!)
    end

    it 'arms the deferred rebuild (and its repagination ticker) on a stale-size hit' do
      allow(pagination_cache_preloader).to receive(:preload)
        .and_return(preload_result.new(:stale, 'k'))
      allow(controller).to receive(:defer_page_map?).and_return(true)

      sequence.start(controller)

      expect(controller).not_to have_received(:clear_defer_page_map!)
      expect(controller).to have_received(:arm_deferred_page_map!)
      expect(controller).to have_received(:schedule_background_page_map_build)
    end
  end
end
