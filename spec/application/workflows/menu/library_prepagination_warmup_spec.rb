# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::LibraryPrepaginationWarmup do
  # Runs the submitted block synchronously so the batch can be asserted inline.
  let(:worker) do
    Class.new do
      def submit(&block)
        block.call
        self
      end

      def shutdown(*); end
    end.new
  end

  let(:background_worker_builder) do
    Class.new do
      include Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder

      def initialize(worker)
        @worker = worker
      end

      def build(name:, logger:)
        @worker
      end
    end.new(worker)
  end

  let(:cache_availability) do
    Class.new do
      include Shoko::Application::Ports::Outbound::CacheAvailability

      def cache_available?(_path)
        true
      end
    end.new
  end

  let(:document) { instance_double('Document', cached?: true, chapter_count: 12) }
  let(:document_loader) do
    Class.new do
      include Shoko::Application::Ports::Outbound::DocumentLoader

      def initialize(document)
        @document = document
      end

      def load(path:, progress_reporter: nil, background_worker: nil)
        @document
      end
    end.new(document)
  end

  let(:runtime_context) do
    Class.new do
      include Shoko::Application::Ports::Outbound::ReaderRuntimeContext

      def terminal_size
        Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 100, height: 40)
      end
    end.new
  end

  let(:catalog_service) do
    instance_double('CatalogService',
                    cached_library_entries: [{ book_path: '/books/a.epub' }, { book_path: '/books/b.epub' }])
  end
  let(:page_calculator) { spy('PageCalculator') }
  let(:progress_writer) do
    Class.new do
      include Shoko::Application::Ports::Outbound::PrepaginationProgressWriter

      attr_reader :events

      def initialize
        @events = []
      end

      def start(total:, paths:)
        @events << [:start, total, paths]
      end

      def report(done:)
        @events << [:report, done]
      end

      def finish
        @events << [:finish]
      end
    end.new
  end
  let(:logger) { instance_double('Logger', debug: nil) }
  let(:clock) do
    Class.new do
      include Shoko::Application::Ports::Outbound::Clock

      def monotonic_now
        0.0
      end
    end.new
  end
  # All-zero so the spec never sleeps or reprioritises the test thread.
  let(:throttle) do
    described_class::Throttle.new(
      worker_priority: nil, startup_settle: 0.0, chapter_ratio: 0.0,
      min_yield: 0.0, max_yield: 0.0, inter_book_pause: 0.0
    )
  end

  let(:config) do
    Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
      prepaginate_on_resize: prepaginate_on_resize,
      last_paginated_size: last_paginated_size,
      page_numbering_mode: :dynamic
    )
  end
  let(:prepaginate_on_resize) { true }
  let(:last_paginated_size) { nil }

  let(:app_config_store) do
    store_config = config
    Class.new do
      def initialize(config)
        @config = config
      end

      def load
        @config
      end

      def save(config)
        @config = config
      end
    end.new(store_config)
  end

  subject(:warmup) do
    described_class.new(
      deps: described_class::Dependencies.new(
        catalog_service: catalog_service,
        cache_availability: cache_availability,
        document_loader: document_loader,
        page_calculator: page_calculator,
        app_config_store: app_config_store,
        reader_runtime_context: runtime_context,
        progress_writer: progress_writer,
        background_worker_builder: background_worker_builder,
        clock: clock,
        logger: logger
      ),
      throttle: throttle
    )
  end

  context 'when the setting is off' do
    let(:prepaginate_on_resize) { false }

    it 'does nothing' do
      expect(warmup.start).to eq(:disabled)
      expect(page_calculator).not_to have_received(:build_dynamic_map!)
    end
  end

  context 'when the library was already paginated at the current size' do
    let(:last_paginated_size) { '100x40' }

    it 'skips the batch' do
      expect(warmup.start).to eq(:unchanged)
      expect(progress_writer.events).to be_empty
    end
  end

  context 'when enabled and the size changed' do
    it 'paginates every cached book and reports progress' do
      expect(warmup.start).to eq(:started)

      expect(page_calculator).to have_received(:reset_session!).twice
      expect(page_calculator).to have_received(:build_dynamic_map!)
        .with(100, 40, document, sidebar_visible: false, config_reader: kind_of(Object)).twice
      expect(progress_writer.events).to eq(
        [[:start, 2, ['/books/a.epub', '/books/b.epub']], [:report, 1], [:report, 2], [:finish]]
      )
    end

    it 'records the size it paginated for so a later run is skipped' do
      warmup.start

      expect(app_config_store.load.last_paginated_size).to eq('100x40')
    end

    it 'uses the absolute map builder in absolute page-numbering mode' do
      allow(app_config_store).to receive(:load).and_return(
        Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(
          prepaginate_on_resize: true, last_paginated_size: nil, page_numbering_mode: :absolute
        )
      )

      warmup.start

      expect(page_calculator).to have_received(:build_absolute_map!).twice
      expect(page_calculator).not_to have_received(:build_dynamic_map!)
    end
  end

  describe '#cancel' do
    it 'shuts the worker down' do
      warmup.start # builds the worker
      expect(worker).to receive(:shutdown)
      warmup.cancel
    end
  end
end
