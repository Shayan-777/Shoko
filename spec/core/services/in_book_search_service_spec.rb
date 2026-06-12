# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::InBookSearchService do
  let(:chapter_class) do
    Class.new do
      def initialize(title:, lines:)
        @title = title
        @lines = lines
      end

      def title
        @title
      end

      def lines
        @lines
      end

      def metadata
        {}
      end
    end
  end
  let(:document_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::ReaderDocument

      attr_reader :chapters

      def initialize(chapters:)
        @chapters = chapters
      end

      def canonical_path
        '/books/test.epub'
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

      def toc_entries
        []
      end
    end
  end

  let(:document) do
    document_class.new(
      chapters: [
        chapter_class.new(title: 'First', lines: ['There are many things to do today.']),
        chapter_class.new(title: 'Second', lines: ['Many people read many books.']),
      ]
    )
  end
  let(:dynamic_page_source_class) do
    Class.new do
      include Shoko::Application::Ports::Outbound::DynamicPageSource

      attr_reader :pages_data

      def initialize(pages_data:)
        @pages_data = pages_data
        @hydrated_pages = {}
      end

      def set_page(page_index, page)
        @hydrated_pages[page_index] = page
      end

      def get_page(page_index, width: nil, height: nil)
        @hydrated_pages.fetch(page_index, @pages_data[page_index])
      end
    end
  end

  subject(:service) { described_class.new(document: document) }

  it 'finds matches across chapters with context' do
    result = service.search('many')

    expect(result.query).to eq('many')
    expect(result.total_matches).to eq(3)
    expect(result.matches.length).to eq(3)
    expect(result.matches.first.chapter_title).to eq('First')
    expect(result.matches.first.before).to include('are')
    expect(result.matches.first.match.downcase).to eq('many')
    expect(result.matches.first.after).to include('things')
  end

  it 'matches full words for simple word queries' do
    document = document_class.new(
      chapters: [chapter_class.new(title: 'Test', lines: ['many manifold manymany'])]
    )
    result = described_class.new(document: document).search('many')

    expect(result.total_matches).to eq(1)
    expect(result.matches.first.match.downcase).to eq('many')
  end

  it 'caps the number of returned matches while keeping full total count' do
    result = service.search('many', max_results: 2)

    expect(result.matches.length).to eq(2)
    expect(result.total_matches).to eq(3)
  end

  it 'late-binds the document so a cached-book open (document loaded after build) is searchable' do
    published = nil
    service = described_class.new(document: nil, document_provider: -> { published })

    expect(service.search('many').total_matches).to eq(0)

    published = document
    result = service.search('many')

    expect(result.total_matches).to eq(3)
    expect(result.matches.first.chapter_title).to eq('First')
  end

  it 'returns empty result for blank query' do
    result = service.search('   ')

    expect(result.total_matches).to eq(0)
    expect(result.matches).to eq([])
  end

  it 'scans all chapters through get_chapter when chapter content is lazily hydrated' do
    all_chapters = [
      chapter_class.new(title: 'First', lines: ['Only first chapter is preloaded.']),
      chapter_class.new(title: 'Second', lines: ['There are many examples in here.']),
      chapter_class.new(title: 'Third', lines: ['Many readers find many references.']),
    ]

    lazy_document = Class.new do
      include Shoko::Application::Ports::Outbound::ReaderDocument

      attr_reader :chapters

      def initialize(chapters)
        @all_chapters = chapters
        @chapters = [chapters.first]
      end

      def chapter_count
        @all_chapters.length
      end

      def get_chapter(index)
        @all_chapters[index]
      end

      def canonical_path
        '/books/lazy.epub'
      end

      def cached?
        false
      end

      def toc_entries
        []
      end
    end.new(all_chapters)

    result = described_class.new(document: lazy_document).search('many')

    expect(result.total_matches).to eq(3)
    expect(result.matches.map(&:chapter_title)).to include('Second', 'Third')
  end

  it 'uses active dynamic wrapped page lines when page numbering is dynamic' do
    page_calculator = dynamic_page_source_class.new(
      pages_data: [
        {
          chapter_index: 0,
          start_line: 10,
          lines: ['There are many', 'things to do today.'],
        },
        {
          chapter_index: 1,
          start_line: 20,
          lines: ['Many people read', 'many books.'],
        },
      ]
    )
    config_reader = instance_double('ConfigReader', page_numbering_mode: :dynamic)
    service = described_class.new(document: document, page_calculator: page_calculator, config_reader: config_reader)

    result = service.search('many')

    expect(result.total_matches).to eq(3)
    expect(result.matches.map(&:line_index)).to eq([10, 20, 21])
    expect(result.matches.map(&:chapter_title)).to eq(%w[First Second Second])
    expect(result.matches.map(&:line_space)).to eq(%i[wrapped wrapped wrapped])
    expect(result.matches.map(&:page_index)).to eq([0, 1, 1])
    # per-page line position (for display), distinct from the chapter-absolute line_index
    expect(result.matches.map(&:page_line_index)).to eq([0, 0, 1])
  end

  it 'labels matches with the numbered fallback when a dynamic page references a missing chapter' do
    page_calculator = dynamic_page_source_class.new(
      pages_data: [
        {
          # Stale cached page maps can point past the resolvable chapters;
          # the search must still return the match instead of crashing.
          chapter_index: 99,
          start_line: 0,
          lines: ['There are many things here.'],
        },
      ]
    )
    config_reader = instance_double('ConfigReader', page_numbering_mode: :dynamic)
    service = described_class.new(document: document, page_calculator: page_calculator, config_reader: config_reader)

    result = service.search('many')

    expect(result.total_matches).to eq(1)
    expect(result.matches.first.chapter_title).to eq('Chapter 100')
  end

  it 'falls back to the complete chapter scan when only some pages are hydrated' do
    page_calculator = dynamic_page_source_class.new(
      pages_data: [
        # Hydrated page: scanning just this one would silently miss the
        # matches that live on the unhydrated page below.
        { chapter_index: 0, start_line: 0, lines: ['There are many things to do today.'] },
        { chapter_index: 1, start_line: 0 },
      ]
    )
    config_reader = instance_double('ConfigReader', page_numbering_mode: :dynamic)
    service = described_class.new(document: document, page_calculator: page_calculator, config_reader: config_reader)

    result = service.search('many')

    expect(result.total_matches).to eq(3)
    expect(result.matches.map(&:line_space)).to all(eq(:chapter))
  end

  it 'falls back to chapter lines when cached dynamic pages have no hydrated line content yet' do
    page_calculator = dynamic_page_source_class.new(
      pages_data: [
        {
          chapter_index: 0,
          start_line: 10,
          end_line: 11,
        },
        {
          chapter_index: 1,
          start_line: 20,
          end_line: 21,
        },
      ]
    )
    config_reader = instance_double('ConfigReader', page_numbering_mode: :dynamic)
    service = described_class.new(document: document, page_calculator: page_calculator, config_reader: config_reader)

    result = service.search('many')

    expect(result.total_matches).to eq(3)
    expect(result.matches.map(&:line_index)).to eq([0, 0, 0])
    expect(result.matches.map(&:chapter_title)).to eq(%w[First Second Second])
    expect(result.matches.map(&:line_space)).to eq(%i[chapter chapter chapter])
    expect(result.matches.map(&:page_index)).to eq([nil, nil, nil])
  end

  it 'fails fast (never silently) when the dynamic collaborator lacks the contract' do
    # The core trusts its typed collaborator instead of defensively probing it
    # (hexagonal_migration_guardrails forbids respond_to?/is_a? in core). A
    # non-conforming collaborator therefore surfaces a NoMethodError when the
    # dynamic-page path runs — it is never silently ignored.
    service = described_class.new(document: document, page_calculator: Object.new)
    expect { service.search('Alice') }.to raise_error(NoMethodError, /pages_data/)
  end
end
