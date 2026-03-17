# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::CatalogService do
  let(:scanner) { double('LibraryScanner') }
  let(:metadata_reader) { double('MetadataReader') }

  before do
    allow(scanner).to receive(:is_a?).and_return(false)
    allow(scanner).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::LibraryScanner)
      .and_return(true)

    allow(metadata_reader).to receive(:is_a?).and_return(false)
    allow(metadata_reader).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::MetadataReader)
      .and_return(true)
  end

  it 'adds last_accessed from recent files when listing cached books' do
    cached_repo = double('CachedRepo', list_entries: [{ epub_path: '/tmp/book.epub', title: 'Book' }])
    recent_repo = double('RecentRepo', load: [{ 'path' => '/tmp/book.epub', 'accessed' => '2024-01-01T00:00:00Z' }])

    service = described_class.new(
      library_scanner: scanner,
      metadata_reader: metadata_reader,
      cached_library_repository: cached_repo,
      recent_files_repository: recent_repo
    )
    entries = service.cached_library_entries

    expect(entries.first[:last_accessed]).to eq('2024-01-01T00:00:00Z')
  end

  it 'returns an empty list when cached repository is not available' do
    service = described_class.new(
      library_scanner: scanner,
      metadata_reader: metadata_reader
    )

    expect(service.cached_library_entries).to eq([])
  end

  it 'returns an empty list when no cached entries exist' do
    cached_repo = double('CachedRepo', list_entries: [])

    service = described_class.new(
      library_scanner: scanner,
      metadata_reader: metadata_reader,
      cached_library_repository: cached_repo
    )

    expect(service.cached_library_entries).to eq([])
  end

  it 'normalizes extracted metadata to symbol keys' do
    allow(metadata_reader).to receive(:extract_metadata).with('/tmp/book.epub').and_return({
                                                                                             'title' => 'Book',
                                                                                             'author' => 'Writer',
                                                                                           })

    service = described_class.new(
      library_scanner: scanner,
      metadata_reader: metadata_reader
    )

    expect(service.metadata_for('/tmp/book.epub')).to eq(title: 'Book', author: 'Writer')
  end
end
