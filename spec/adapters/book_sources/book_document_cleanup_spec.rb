# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::BookDocument do
  let(:logger) { instance_double('Logger', error: nil, debug: nil) }

  it 'removes dead private helper APIs no longer used by render/import paths' do
    private_methods = described_class.private_instance_methods

    expect(private_methods).not_to include(:enqueue_async_formatting)
    expect(private_methods).not_to include(:assign_toc_entries)
    expect(private_methods).not_to include(:normalize_toc_href)
  end

  it 'still formats chapters through active formatting path' do
    chapter = Shoko::Core::Models::Chapter.new(
      number: '1',
      title: 'Chapter 1',
      lines: ['raw line'],
      metadata: {},
      blocks: nil,
      raw_content: '<p>raw line</p>'
    )
    book = Shoko::Core::Models::BookData.new(
      title: 'Book',
      language: 'en',
      authors: [],
      chapters: [chapter],
      toc_entries: [],
      opf_path: nil,
      spine: [],
      chapter_hrefs: [],
      resources: {},
      metadata: {},
      container_path: nil,
      container_xml: nil,
      format_data: {}
    )

    result = Struct.new(:book, :loaded_from_cache, :source_path, :cache_path, :payload, keyword_init: true).new(
      book: book,
      loaded_from_cache: false,
      source_path: '/tmp/book.epub',
      cache_path: nil,
      payload: nil
    )
    cache = instance_double('BookCachePipeline', load: result)
    formatting_service = instance_double('FormattingService')

    allow(formatting_service).to receive(:ensure_formatted!) do |_document, _chapter_index, current_chapter|
      current_chapter.lines = ['formatted line']
      current_chapter.blocks = [:paragraph]
    end

    document = described_class.new(
      '/tmp/book.epub',
      logger: logger,
      formatting_service: formatting_service,
      book_cache: cache
    )

    formatted = document.get_chapter(0)

    expect(formatted.lines).to eq(['formatted line'])
    expect(formatted.blocks).to eq([:paragraph])
  end

  it 'allows image-only or blank chapters that produce zero lines after formatting' do
    chapter = Shoko::Core::Models::Chapter.new(
      number: '1',
      title: 'Cover',
      lines: nil,
      metadata: {},
      blocks: nil,
      raw_content: '<img src="cover.jpg" />'
    )
    book = Shoko::Core::Models::BookData.new(
      title: 'Book',
      language: 'en',
      authors: [],
      chapters: [chapter],
      toc_entries: [],
      opf_path: nil,
      spine: [],
      chapter_hrefs: [],
      resources: {},
      metadata: {},
      container_path: nil,
      container_xml: nil,
      format_data: {}
    )

    result = Struct.new(:book, :loaded_from_cache, :source_path, :cache_path, :payload, keyword_init: true).new(
      book: book,
      loaded_from_cache: false,
      source_path: '/tmp/book.epub',
      cache_path: nil,
      payload: nil
    )
    cache = instance_double('BookCachePipeline', load: result)
    formatting_service = instance_double('FormattingService')

    allow(formatting_service).to receive(:ensure_formatted!) do |_document, _chapter_index, current_chapter|
      current_chapter.lines = []
      current_chapter.blocks = [:image]
    end

    document = described_class.new(
      '/tmp/book.epub',
      logger: logger,
      formatting_service: formatting_service,
      book_cache: cache
    )

    expect { document.get_chapter(0) }.not_to raise_error
    expect(document.get_chapter(0).lines).to eq([])
  end
end
