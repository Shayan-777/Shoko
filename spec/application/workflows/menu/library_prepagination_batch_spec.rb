# frozen_string_literal: true

require 'spec_helper'
require 'shoko/application/workflows/menu/library_prepagination_batch'

RSpec.describe Shoko::Application::Workflows::Menu::LibraryPrepaginationBatch do
  let(:cache_availability) do
    Class.new do
      include Shoko::Application::Ports::Outbound::CacheAvailability

      def cache_available?(path)
        !path.end_with?('uncached.epub')
      end
    end.new
  end

  let(:document) { instance_double(Shoko::Application::Models::ReaderDocument, cached?: true, chapter_count: 12) }
  let(:document_loader) do
    Class.new do
      include Shoko::Application::Ports::Outbound::DocumentLoader

      def initialize(document)
        @document = document
      end

      def load(path:, progress_reporter: nil)
        @document
      end
    end.new(document)
  end

  let(:catalog_service) do
    instance_double(
      Shoko::Application::UseCases::CatalogService,
      cached_library_entries: [
        { book_path: '/books/a.epub' },
        { book_path: '/books/b.epub' },
        { book_path: '/books/uncached.epub' },
      ]
    )
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

  let(:page_numbering_mode) { :dynamic }
  let(:config) do
    Shoko::Application::Ports::Outbound::State::ConfigSnapshot.build(page_numbering_mode: page_numbering_mode)
  end
  let(:app_config_store) { instance_double(Shoko::Application::Ports::Outbound::AppConfigStore, load: config) }
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging, debug: nil) }

  subject(:batch) do
    described_class.new(
      deps: described_class::Dependencies.new(
        catalog_service: catalog_service,
        cache_availability: cache_availability,
        document_loader: document_loader,
        page_calculator: page_calculator,
        app_config_store: app_config_store,
        progress_writer: progress_writer,
        logger: logger
      )
    )
  end

  it 'paginates every cached book at the given size and reports progress' do
    expect(batch.run(width: 100, height: 40)).to eq(:completed)

    expect(page_calculator).to have_received(:reset_session!).twice
    expect(page_calculator).to have_received(:build_dynamic_map!)
      .with(100, 40, document, config_reader: kind_of(Object)).twice
    expect(progress_writer.events).to eq(
      [[:start, 2, ['/books/a.epub', '/books/b.epub']], [:report, 1], [:report, 2], [:finish]]
    )
  end

  context 'in absolute page-numbering mode' do
    let(:page_numbering_mode) { :absolute }

    it 'uses the absolute map builder' do
      batch.run(width: 100, height: 40)

      expect(page_calculator).to have_received(:build_absolute_map!).twice
      expect(page_calculator).not_to have_received(:build_dynamic_map!)
    end
  end

  context 'when one book fails to paginate' do
    before do
      allow(page_calculator).to receive(:build_dynamic_map!)
        .and_raise(Shoko::BookParseError.new('boom', '/books/a.epub'))
    end

    it 'continues with the rest and still finishes' do
      expect(batch.run(width: 100, height: 40)).to eq(:completed)

      expect(progress_writer.events).to include([:report, 1], [:report, 2], [:finish])
    end
  end

  context 'when there is nothing to paginate' do
    let(:catalog_service) { instance_double(Shoko::Application::UseCases::CatalogService, cached_library_entries: []) }

    it 'completes without starting progress' do
      expect(batch.run(width: 100, height: 40)).to eq(:completed)

      expect(progress_writer.events).to eq([[:finish]])
    end
  end

  context 'when library discovery itself fails' do
    let(:catalog_service) { instance_double(Shoko::Application::UseCases::CatalogService) }

    before do
      allow(catalog_service).to receive(:cached_library_entries)
        .and_raise(Shoko::StorageError.new('catalog_scan', '/library', 'boom'))
    end

    it 'fails the batch — no work ran, so it must not count as done' do
      # The parent warmup persists the terminal-size signature on :completed;
      # reporting a failed discovery as done would suppress every retry at
      # this size.
      expect(batch.run(width: 100, height: 40)).to eq(:failed)

      expect(page_calculator).not_to have_received(:build_dynamic_map!)
      expect(progress_writer.events).to eq([[:finish]])
    end
  end
end
