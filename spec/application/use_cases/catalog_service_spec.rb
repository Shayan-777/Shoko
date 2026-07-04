# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Shoko::Application::UseCases::CatalogService do
  class CatalogServiceSpecExecutor
    include Shoko::Application::Ports::Outbound::AsyncExecutor

    attr_reader :jobs

    def initialize
      @jobs = []
      @shutdown = false
    end

    def submit(&block)
      @jobs << block
    end

    def run_next
      @jobs.shift&.call
    end

    def shutdown(_timeout = nil)
      @shutdown = true
    end

    def shutdown?
      @shutdown == true
    end
  end

  class CatalogServiceSpecWorkerBuilder
    include Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder

    attr_reader :built_with, :executor

    def initialize(executor)
      @executor = executor
      @built_with = []
    end

    def build(name:, logger:)
      @built_with << { name: name, logger: logger }
      @executor
    end
  end

  let(:scanner) { double('LibraryScanner') }
  let(:metadata_reader) { double('MetadataReader') }
  let(:file_probe) { double('FileProbe') }
  let(:display_cache) do
    Shoko::Adapters::Storage::Repositories::DisplayMetadataCacheRepository.new(cache_root: File.join(@tmpdir, 'cache'))
  end

  around do |example|
    Dir.mktmpdir { |dir| @tmpdir = dir; example.run }
  end

  before do
    allow(scanner).to receive(:is_a?).and_return(false)
    allow(scanner).to receive(:is_a?)
      .with(Shoko::Application::Ports::Outbound::LibraryScanner)
      .and_return(true)

    allow(metadata_reader).to receive(:is_a?).and_return(false)
    allow(metadata_reader).to receive(:is_a?)
      .with(Shoko::Application::Ports::Outbound::MetadataReader)
      .and_return(true)

    allow(file_probe).to receive(:is_a?).and_return(false)
    allow(file_probe).to receive(:is_a?)
      .with(Shoko::Application::Ports::Outbound::FileProbe)
      .and_return(true)
    # Defer to real filesystem when the path exists (matches the bit-for-bit
    # behavior of the previous File.* fallback inside catalog_service);
    # return safe sentinels otherwise.
    allow(file_probe).to receive(:size) { |path| File.exist?(path) ? File.size(path) : 0 }
    allow(file_probe).to receive(:mtime) { |path| File.exist?(path) ? File.mtime(path).iso8601 : nil }
  end

  def build_service(**overrides)
    described_class.new(
      **{
        library_scanner: scanner,
        metadata_reader: metadata_reader,
        file_probe: file_probe,
      }.merge(overrides)
    )
  end

  it 'adds last_accessed from recent files when listing cached books' do
    cached_repo = double('CachedRepo', list_entries: [{ epub_path: '/tmp/book.epub', title: 'Book' }])
    recent_repo = double('RecentRepo', load: [{ 'path' => '/tmp/book.epub', 'accessed' => '2024-01-01T00:00:00Z' }])

    service = build_service(
      cached_library_repository: cached_repo,
      recent_files_repository: recent_repo
    )
    entries = service.cached_library_entries

    expect(entries.first[:last_accessed]).to eq('2024-01-01T00:00:00Z')
  end

  it 'returns an empty list when cached repository is not available' do
    service = build_service

    expect(service.cached_library_entries).to eq([])
  end

  it 'returns an empty list when no cached entries exist' do
    cached_repo = double('CachedRepo', list_entries: [])

    service = build_service(cached_library_repository: cached_repo)

    expect(service.cached_library_entries).to eq([])
  end

  it 'passes preserved-entry scan requests through to the scanner' do
    allow(scanner).to receive(:start_scan)
    service = build_service

    service.start_scan(force: true, preserve_entries: true)

    expect(scanner).to have_received(:start_scan).with(force: true, preserve_entries: true)
  end

  it 'normalizes extracted metadata to symbol keys' do
    allow(metadata_reader).to receive(:extract_metadata).with('/tmp/book.epub').and_return({
                                                                                             'title' => 'Book',
                                                                                             'author' => 'Writer',
                                                                                           })

    service = build_service

    expect(service.metadata_for('/tmp/book.epub')).to eq(title: 'Book', author: 'Writer')
  end

  it 'uses a valid persistent success cache for blocking metadata reads' do
    path = File.join(@tmpdir, 'book.epub')
    File.write(path, 'book')
    display_cache.write_success(
      path: path,
      size: File.size(path),
      modified: File.mtime(path).iso8601,
      metadata: { title: 'Cached Book', authors: ['Cached Writer'] }
    )

    expect(metadata_reader).not_to receive(:extract_metadata)

    service = build_service(display_metadata_cache: display_cache)

    expect(service.metadata_for(path)).to eq(title: 'Cached Book', authors: ['Cached Writer'])
  end

  it 'returns cached display metadata synchronously' do
    display_cache.write_success(
      path: '/tmp/book.epub',
      size: 100,
      modified: '2024-01-01T00:00:00Z',
      metadata: { title: 'Cached Book', authors: ['Writer'] }
    )

    service = build_service(display_metadata_cache: display_cache)

    expect(service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z'))
      .to eq(title: 'Cached Book', authors: ['Writer'])
  end

  it 'schedules one background display metadata extraction on miss and refreshes from memory' do
    executor = CatalogServiceSpecExecutor.new
    builder = CatalogServiceSpecWorkerBuilder.new(executor)
    allow(metadata_reader).to receive(:extract_metadata).with('/tmp/book.epub')
                                                     .and_return(title: 'Async Book', authors: ['Writer'])
    service = build_service(display_metadata_cache: display_cache, background_worker_builder: builder)

    expect(service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z')).to eq({})
    expect(service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z')).to eq({})
    expect(executor.jobs.length).to eq(1)

    executor.run_next

    expect(service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z'))
      .to eq(title: 'Async Book', authors: ['Writer'])
    expect(service.metadata_refresh_pending?).to be(true)
    expect(service.consume_metadata_refresh!).to be(true)
    expect(service.metadata_refresh_pending?).to be(false)
  end

  it 'caches display metadata failures so later sessions do not reparse malformed books' do
    executor = CatalogServiceSpecExecutor.new
    builder = CatalogServiceSpecWorkerBuilder.new(executor)
    allow(metadata_reader).to receive(:extract_metadata).with('/tmp/bad.pdf')
                                                     .and_raise(Shoko::MalformedMetadataInputError, 'bad pdf')
    service = build_service(display_metadata_cache: display_cache, background_worker_builder: builder)

    expect(service.display_metadata_for('/tmp/bad.pdf', size: 200, modified: '2024-01-01T00:00:00Z')).to eq({})
    executor.run_next

    new_executor = CatalogServiceSpecExecutor.new
    new_builder = CatalogServiceSpecWorkerBuilder.new(new_executor)
    fresh_reader = double('MetadataReader')
    allow(fresh_reader).to receive(:is_a?).and_return(false)
    allow(fresh_reader).to receive(:is_a?)
      .with(Shoko::Application::Ports::Outbound::MetadataReader)
      .and_return(true)
    expect(fresh_reader).not_to receive(:extract_metadata)

    fresh_service = described_class.new(
      library_scanner: scanner,
      metadata_reader: fresh_reader,
      file_probe: file_probe,
      display_metadata_cache: display_cache,
      background_worker_builder: new_builder
    )

    expect(fresh_service.display_metadata_for('/tmp/bad.pdf', size: 200, modified: '2024-01-01T00:00:00Z')).to eq({})
    expect(new_executor.jobs).to be_empty
  end

  it 'contains a submit refused by a stopping worker and releases the inflight slot' do
    executor = CatalogServiceSpecExecutor.new
    builder = CatalogServiceSpecWorkerBuilder.new(executor)
    allow(executor).to receive(:submit)
      .and_raise(Shoko::Adapters::Storage::BackgroundWorker::WorkerStoppedError, 'worker is shutting down')
    service = build_service(display_metadata_cache: display_cache, background_worker_builder: builder)

    expect do
      service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z')
      service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z')
    end.not_to raise_error

    # Both calls submitted: the first failure released the inflight marker
    # instead of leaving the extraction permanently latched as in-flight.
    expect(executor).to have_received(:submit).twice
  end

  it 'clears in-memory metadata when entries are updated' do
    allow(scanner).to receive(:update_entries)
    display_cache.write_success(
      path: '/tmp/book.epub',
      size: 100,
      modified: '2024-01-01T00:00:00Z',
      metadata: { title: 'Old Title' }
    )
    service = build_service(display_metadata_cache: display_cache)
    expect(service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z'))
      .to eq(title: 'Old Title')

    display_cache.write_success(
      path: '/tmp/book.epub',
      size: 100,
      modified: '2024-01-01T00:00:00Z',
      metadata: { title: 'New Title' }
    )
    service.update_entries([])

    expect(service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z'))
      .to eq(title: 'New Title')
  end

  it 'shuts down the owned display metadata worker during cleanup' do
    allow(scanner).to receive(:cleanup)
    executor = CatalogServiceSpecExecutor.new
    builder = CatalogServiceSpecWorkerBuilder.new(executor)
    service = build_service(display_metadata_cache: display_cache, background_worker_builder: builder)

    service.display_metadata_for('/tmp/book.epub', size: 100, modified: '2024-01-01T00:00:00Z')
    service.cleanup

    expect(executor.shutdown?).to be(true)
  end
end
