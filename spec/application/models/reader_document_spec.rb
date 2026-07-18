# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Models::ReaderDocument do
  def book_with(chapters:)
    Shoko::Core::Models::BookData.new(
      title: 'Book',
      language: 'en',
      authors: [],
      chapters: chapters,
      toc_entries: [],
      resources: {},
      metadata: {},
      chapters_generation: nil,
      format_data: { format: :epub }
    )
  end

  it 'exposes loaded book data through the reader document port' do
    chapter = Shoko::Core::Models::Chapter.new(number: '1', title: 'One', lines: nil)
    document = described_class.new(
      book: book_with(chapters: [chapter]),
      source_path: '/tmp/book.epub',
      cache_path: '/tmp/book.cache',
      cache_sha: 'abc',
      loaded_from_cache: true
    )

    expect(document).to be_a(Shoko::Application::Ports::Internal::ReaderDocument)
    expect(document.chapter_count).to eq(1)
    expect(document.get_chapter(0).lines).to eq([])
    expect(document.cached?).to be(true)
    expect(document.canonical_path).to eq('/tmp/book.epub')
  end

  it 'rejects empty imported books' do
    expect do
      described_class.new(book: book_with(chapters: []), source_path: '/tmp/book.epub')
    end.to raise_error(Shoko::BookParseError, /book contains no chapters/)
  end
end
