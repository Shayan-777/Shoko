# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::BookDocumentLoader do
  CacheEntry = Shoko::Application::Ports::Outbound::BookCacheStore::CacheEntry

  class LoaderSpecCacheStore
    include Shoko::Application::Ports::Outbound::BookCacheStore

    attr_reader :written

    def initialize(fetch_entry: nil, write_entry: nil)
      @fetch_entry = fetch_entry
      @write_entry = write_entry
      @written = []
    end

    def fetch(_path, strict: true)
      @fetch_entry
    end

    def write(path, book_data)
      @written << [path, book_data]
      @write_entry
    end
  end

  class LoaderSpecImporter
    include Shoko::Application::Ports::Outbound::BookImporterResolver

    attr_reader :imported_paths

    def initialize(book)
      @book = book
      @imported_paths = []
    end

    def import(path, progress_reporter: nil, runtime_config: nil)
      _ = [progress_reporter, runtime_config]
      @imported_paths << path
      @book
    end
  end

  def book
    chapter = Shoko::Core::Models::Chapter.new(number: '1', title: 'One', lines: ['line'])
    Shoko::Core::Models::BookData.new(
      title: 'Book',
      language: 'en',
      authors: [],
      chapters: [chapter],
      toc_entries: [],
      resources: {},
      metadata: {},
      chapters_generation: nil,
      format_data: { format: :epub }
    )
  end

  def entry(book_data, loaded_from_cache:)
    CacheEntry.new(
      book: book_data,
      cache_path: '/tmp/book.cache',
      source_path: '/tmp/book.epub',
      source_sha: 'abc',
      loaded_from_cache: loaded_from_cache,
      payload: nil
    )
  end

  it 'returns cached documents without importing' do
    book_data = book
    cache_store = LoaderSpecCacheStore.new(fetch_entry: entry(book_data, loaded_from_cache: true))
    importer = LoaderSpecImporter.new(book_data)

    document = described_class.new(
      book_cache_store: cache_store,
      book_importer_resolver: importer,
      runtime_config: nil
    ).load(path: '/tmp/book.epub')

    expect(document.cached?).to be(true)
    expect(importer.imported_paths).to eq([])
  end

  it 'imports, writes cache, and returns an application reader document on cache miss' do
    book_data = book
    cache_store = LoaderSpecCacheStore.new(write_entry: entry(book_data, loaded_from_cache: false))
    importer = LoaderSpecImporter.new(book_data)

    document = described_class.new(
      book_cache_store: cache_store,
      book_importer_resolver: importer,
      runtime_config: nil
    ).load(path: '/tmp/book.epub')

    expect(importer.imported_paths).to eq(['/tmp/book.epub'])
    expect(cache_store.written).to eq([['/tmp/book.epub', book_data]])
    expect(document).to be_a(Shoko::Application::Models::ReaderDocument)
    expect(document.cached?).to be(false)
  end
end
