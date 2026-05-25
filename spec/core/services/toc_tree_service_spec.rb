# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::TocTreeService do
  subject(:service) { described_class.new }

  it 'builds fallback entries from chapters when toc is empty' do
    chapter_class = Class.new do
      include Shoko::Core::Ports::Outbound::ReaderChapter

      def initialize(title:)
        @title = title
      end

      def title
        @title
      end

      def lines
        []
      end

      def metadata
        {}
      end
    end
    document_class = Class.new do
      include Shoko::Core::Ports::Outbound::ReaderDocument

      def initialize(chapters)
        @chapters = chapters
      end

      def toc_entries
        []
      end

      def canonical_path
        '/books/toc.epub'
      end

      def cached?
        false
      end

      def chapter_count
        @chapters.length
      end

      def get_chapter(index)
        @chapters[index]
      end
    end
    chapters = [chapter_class.new(title: 'Intro'), chapter_class.new(title: '')]
    doc = document_class.new(chapters)

    entries = service.entries_for(doc)

    expect(entries.map(&:title)).to eq(['Intro', 'Chapter 2'])
    expect(entries.map(&:level)).to eq([0, 0])
    expect(entries.map(&:chapter_index)).to eq([0, 1])
  end

  it 'returns filtered entries with ancestors and ignores collapse when filter is active' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section B', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1)
    ]

    visible = service.visible_indices(entries, collapsed: [0], filter_text: 'section b', filter_active: true)

    expect(visible).to eq([0, 2])
  end

  it 'applies collapse when filter is inactive' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section B', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1)
    ]

    visible = service.visible_indices(entries, collapsed: [0], filter_text: '', filter_active: false)

    expect(visible).to eq([0, 3])
  end

  it 're-targets hidden selection to a visible entry' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1)
    ]

    selected = service.ensure_visible_selection(entries, [0], 1, filter_text: '', filter_active: false)

    expect(selected).to eq(0)
  end

  it 'moves to the previous TOC target without relying on Ruby 4 Array APIs' do
    expect(service.target_index([0, 2, 5], 5, -1)).to eq(2)
    expect(service.target_index([0, 2, 5], 0, -1)).to eq(0)
  end

  it 'moves to the next TOC target and clamps at the end' do
    expect(service.target_index([0, 2, 5], 0, 1)).to eq(2)
    expect(service.target_index([0, 2, 5], 5, 1)).to eq(5)
  end

  it 'uses the nearest previous visible entry when no visible parent exists' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 2', href: nil, level: 0, chapter_index: 1),
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 3', href: nil, level: 0, chapter_index: 2)
    ]

    selected = service.ensure_visible_selection(entries, [], 1, filter_text: 'Chapter 1', filter_active: true)

    expect(selected).to eq(0)
  end

  it 'filters TOC entries without relying on external Set loading order' do
    entries = [
      Shoko::Core::Models::TOCEntry.new(title: 'Chapter 1', href: nil, level: 0, chapter_index: 0),
      Shoko::Core::Models::TOCEntry.new(title: 'Section A', href: nil, level: 1, chapter_index: 0)
    ]

    expect(service.visible_indices(entries, collapsed: [], filter_text: 'section', filter_active: true)).to eq([0, 1])
  end
end
