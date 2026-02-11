# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::InBookSearchService do
  let(:chapter_class) { Struct.new(:title, :lines, keyword_init: true) }
  let(:document_class) { Struct.new(:chapters, keyword_init: true) }

  let(:document) do
    document_class.new(
      chapters: [
        chapter_class.new(title: 'First', lines: ['There are many things to do today.']),
        chapter_class.new(title: 'Second', lines: ['Many people read many books.']),
      ]
    )
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
    end.new(all_chapters)

    result = described_class.new(document: lazy_document).search('many')

    expect(result.total_matches).to eq(3)
    expect(result.matches.map(&:chapter_title)).to include('Second', 'Third')
  end
end
